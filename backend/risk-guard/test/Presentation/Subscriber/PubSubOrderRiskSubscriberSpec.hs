{-# OPTIONS_GHC -fno-hpc #-}

{- | Tests for 'Presentation.Subscriber.PubSubOrderRiskSubscriber'.

 TST-PRES-001: Ack returned on successful processing.
 TST-PRES-002: Ack returned on duplicate event.
 TST-PRES-003: Nack (non-retryable) returned on decode failure.
 TST-PRES-008: decode failure returns 200 ack; valid CloudEvents calls use case.
 TST-PRES-011: withRetry — retryable failure calls use case up to 3 times.

 Test doubles live in this file only. No mock code enters src/.
-}
module Presentation.Subscriber.PubSubOrderRiskSubscriberSpec (spec) where

import Control.Concurrent.MVar (MVar, modifyMVar_, newMVar, readMVar)
import Data.Aeson (encode, object, (.=))
import Data.Base64.Types (extractBase64)
import Data.ByteString.Base64 (encodeBase64)
import Data.ByteString.Lazy qualified as ByteStringLazy
import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.RiskAssessment.Factory (OrdersProposedPayload (..))
import Domain.RiskAssessment.ReasonCode (ReasonCode (..))
import Domain.RiskAssessment.ValueObjects (
  CompliancePolicy (..),
  RiskExposure (..),
  RiskLimits (..),
 )
import Presentation.Subscriber.PubSubOrderRiskSubscriber (
  OrderRiskPushResult (..),
  orderRiskPushResultToStatus,
  processOrderRiskMessageWith,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import UseCase.CheckOrderRisk (CheckOrderRiskResult (..))

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

validUlidText :: Text
validUlidText = "01ARZ3NDEKTSV4RRFFQ69G5FAV"

-- | Build a valid Pub/Sub push body for an orders.proposed event.
buildValidPubSubBody :: Text -> ByteStringLazy.ByteString
buildValidPubSubBody ulidText =
  let cloudEventValue =
        object
          [ "identifier" .= ulidText
          , "eventType" .= ("orders.proposed" :: Text)
          , "occurredAt" .= ("2026-01-15T00:00:00Z" :: Text)
          , "trace" .= ulidText
          , "schemaVersion" .= ("1.0.0" :: Text)
          , "payload"
              .= object
                [ "symbol" .= ("7203.T" :: Text)
                , "side" .= ("BUY" :: Text)
                , "qty" .= (100.0 :: Double)
                ]
          ]
      rawBytes = ByteStringLazy.toStrict (encode cloudEventValue)
      base64Data = extractBase64 (encodeBase64 rawBytes)
   in encode
        ( object
            [ "message"
                .= object
                  [ "messageId" .= ("test-msg-id" :: Text)
                  , "publishTime" .= ("2026-01-15T00:00:00Z" :: Text)
                  , "data" .= base64Data
                  ]
            ]
        )

invalidJsonBody :: ByteStringLazy.ByteString
invalidJsonBody = "not-valid-json{{{"

-- | Fake settings that return safe defaults without Firestore calls.
fakeLoadSettings :: IO (Bool, RiskLimits, CompliancePolicy, RiskExposure)
fakeLoadSettings =
  pure
    ( False
    , RiskLimits
        { dailyLossLimit = 0.05
        , positionConcentrationLimit = 0.20
        , dailyOrderLimit = 50
        }
    , CompliancePolicy
        { restrictedSymbols = []
        , partnerRestrictedSymbols = []
        , blackoutWindows = []
        }
    , RiskExposure
        { dailyLossRate = 0.01
        , positionConcentrationRate = 0.05
        , dailyOrderCount = 5
        }
    )

-- ---------------------------------------------------------------------------
-- Helpers for injectable runner
-- ---------------------------------------------------------------------------

-- | A fake use case runner that records call counts and returns a fixed result.
runFakeUseCase ::
  MVar Int ->
  CheckOrderRiskResult ->
  UTCTime ->
  Bool ->
  RiskLimits ->
  CompliancePolicy ->
  RiskExposure ->
  OrdersProposedPayload ->
  IO CheckOrderRiskResult
runFakeUseCase callCountRef result _currentTime _killSwitchEnabled _riskLimits _compliancePolicy _riskExposure _payload = do
  modifyMVar_ callCountRef (\count -> pure (count + 1))
  pure result

processWithFakeSettingsAndCount ::
  CheckOrderRiskResult ->
  ByteStringLazy.ByteString ->
  IO (OrderRiskPushResult, Int)
processWithFakeSettingsAndCount useCaseResult body = do
  callCountRef <- newMVar (0 :: Int)
  pushResult <-
    processOrderRiskMessageWith
      fakeLoadSettings
      (runFakeUseCase callCountRef useCaseResult)
      body
  callCount <- readMVar callCountRef
  pure (pushResult, callCount)

processWithFakeSettings ::
  CheckOrderRiskResult ->
  ByteStringLazy.ByteString ->
  IO OrderRiskPushResult
processWithFakeSettings useCaseResult body =
  fst <$> processWithFakeSettingsAndCount useCaseResult body

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "Presentation.Subscriber.PubSubOrderRiskSubscriber" $ do
    describe "TST-PRES-001: Ack returned on successful processing" $ do
      it "returns OrderRiskCheckSucceeded (200 ack) when use case returns CheckOrderRiskApproved" $ do
        let body = buildValidPubSubBody validUlidText
        pushResult <- processWithFakeSettings CheckOrderRiskApproved body
        pushResult `shouldBe` OrderRiskCheckSucceeded

      it "returns OrderRiskCheckSucceeded (200 ack) when use case returns CheckOrderRiskRejected" $ do
        let body = buildValidPubSubBody validUlidText
            rejectedResult = CheckOrderRiskRejected KillSwitchEnabled
        pushResult <- processWithFakeSettings rejectedResult body
        pushResult `shouldBe` OrderRiskCheckSucceeded

    describe "TST-PRES-002: Ack returned on duplicate event" $ do
      it "returns OrderRiskCheckDuplicate (200 ack) when use case returns CheckOrderRiskDuplicate" $ do
        let body = buildValidPubSubBody validUlidText
        pushResult <- processWithFakeSettings CheckOrderRiskDuplicate body
        pushResult `shouldBe` OrderRiskCheckDuplicate

    describe "TST-PRES-003: Nack on decode failure (TST-PRES-008 overlap)" $ do
      it "returns OrderRiskSchemaInvalid (200 ack) on invalid JSON body" $ do
        pushResult <- processWithFakeSettings CheckOrderRiskApproved invalidJsonBody
        pushResult `shouldSatisfy` isSchemaInvalid

      it "orderRiskPushResultToStatus: SchemaInvalid maps to Right (HTTP 200 ack)" $ do
        orderRiskPushResultToStatus (OrderRiskSchemaInvalid "test")
          `shouldBe` Right (OrderRiskSchemaInvalid "test")

      it "orderRiskPushResultToStatus: CheckFailed maps to Left (HTTP 500 nack)" $ do
        orderRiskPushResultToStatus (OrderRiskCheckFailed "transient")
          `shouldSatisfy` isLeft

    describe "TST-PRES-011: withRetry — retryable failure calls use case up to 3 times" $ do
      it "calls use case exactly 4 times (1 initial + 3 retries) for retryable failure" $ do
        let body = buildValidPubSubBody validUlidText
            retryableResult = CheckOrderRiskFailed "transient" True
        (_pushResult, callCount) <- processWithFakeSettingsAndCount retryableResult body
        -- withRetry with maxRetries=3 means 1 initial + 3 retries = 4 calls
        callCount `shouldBe` 4

      it "returns OrderRiskCheckFailed after retry exhaustion" $ do
        let body = buildValidPubSubBody validUlidText
            retryableResult = CheckOrderRiskFailed "transient" True
        (pushResult, _) <- processWithFakeSettingsAndCount retryableResult body
        pushResult `shouldBe` OrderRiskCheckFailed "retry_exhausted"

      it "non-retryable failure (retryable=False) calls use case exactly once" $ do
        let body = buildValidPubSubBody validUlidText
            nonRetryableResult = CheckOrderRiskFailed "permanent" False
        (_pushResult, callCount) <- processWithFakeSettingsAndCount nonRetryableResult body
        callCount `shouldBe` 1

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

isSchemaInvalid :: OrderRiskPushResult -> Bool
isSchemaInvalid (OrderRiskSchemaInvalid _) = True
isSchemaInvalid _ = False

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False
