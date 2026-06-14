{-# LANGUAGE OverloadedRecordDot #-}

{- | Pure contract tests for PubSubRiskEventPublisher event builders.

TST-INFRA-005: buildOrdersApprovedEvent has eventType="orders.approved", schemaVersion="1.0.0",
               payload.decision="approved".
TST-INFRA-006: buildOrdersRejectedEvent has eventType="orders.rejected", payload.decision="rejected",
               payload.reasonCode present.
TST-INFRA-007: reasonCodeToWire mappings for all 5 risk-guard reason codes.
-}
module Infrastructure.Publisher.PubSubRiskEventPublisherSpec (spec) where

import Data.Text (Text)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.RiskAssessment (Trace (..))
import Domain.RiskAssessment.Aggregate (
  OrdersApprovedPayload (..),
  OrdersRejectedPayload (..),
 )
import Domain.RiskAssessment.ReasonCode (ReasonCode (..))
import Domain.RiskAssessment.ValueObjects (OrderRiskAssessmentIdentifier (..))
import Infrastructure.Publisher.PubSubRiskEventPublisher (
  OrdersApprovedEventPayload (..),
  OrdersRejectedEventPayload (..),
  buildOrdersApprovedEvent,
  buildOrdersRejectedEvent,
 )
import Infrastructure.Wire.ReasonCodeWire (reasonCodeToWire)
import Messaging.CloudEvent (CloudEvent (..))
import Test.Hspec (Spec, describe, it, shouldBe)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

fixedEventIdentifier :: ULID
fixedEventIdentifier = mkULID 999

approvedPayload :: OrdersApprovedPayload
approvedPayload =
  OrdersApprovedPayload
    { identifier = OrderRiskAssessmentIdentifier{value = mkULID 1}
    , trace = Trace{value = mkULID 100}
    , reasonCode = Nothing
    , actionReasonCode = Nothing
    , evaluatedAt = fixedTime
    }

rejectedPayload :: OrdersRejectedPayload
rejectedPayload =
  OrdersRejectedPayload
    { identifier = OrderRiskAssessmentIdentifier{value = mkULID 2}
    , reasonCode = KillSwitchEnabled
    , trace = Trace{value = mkULID 200}
    }

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Infrastructure.Publisher.PubSubRiskEventPublisher" $ do
  -- TST-INFRA-005
  describe "TST-INFRA-005: buildOrdersApprovedEvent" $ do
    it "sets eventType to 'orders.approved'" $ do
      let event = buildOrdersApprovedEvent fixedEventIdentifier fixedTime approvedPayload
          eventTypeValue = (event :: CloudEvent OrdersApprovedEventPayload).eventType
      eventTypeValue `shouldBe` ("orders.approved" :: Text)

    it "sets schemaVersion to '1.0.0'" $ do
      let event = buildOrdersApprovedEvent fixedEventIdentifier fixedTime approvedPayload
          schemaVersionValue = (event :: CloudEvent OrdersApprovedEventPayload).schemaVersion
      schemaVersionValue `shouldBe` ("1.0.0" :: Text)

    it "sets payload.decision to 'approved'" $ do
      let event = buildOrdersApprovedEvent fixedEventIdentifier fixedTime approvedPayload
          decisionValue = (event :: CloudEvent OrdersApprovedEventPayload).payload.decision
      decisionValue `shouldBe` ("approved" :: Text)

    it "sets occurredAt to injected time" $ do
      let event = buildOrdersApprovedEvent fixedEventIdentifier fixedTime approvedPayload
          occurredAtValue = (event :: CloudEvent OrdersApprovedEventPayload).occurredAt
      occurredAtValue `shouldBe` fixedTime

    it "sets identifier to injected event identifier" $ do
      let event = buildOrdersApprovedEvent fixedEventIdentifier fixedTime approvedPayload
          identifierValue = (event :: CloudEvent OrdersApprovedEventPayload).identifier
      identifierValue `shouldBe` fixedEventIdentifier

    it "sets trace from payload trace" $ do
      let event = buildOrdersApprovedEvent fixedEventIdentifier fixedTime approvedPayload
          traceValue = (event :: CloudEvent OrdersApprovedEventPayload).trace
      traceValue `shouldBe` mkULID 100

    it "sets payload.reasonCode to Nothing when no reason code" $ do
      let event = buildOrdersApprovedEvent fixedEventIdentifier fixedTime approvedPayload
          reasonCodeValue = (event :: CloudEvent OrdersApprovedEventPayload).payload.reasonCode
      reasonCodeValue `shouldBe` (Nothing :: Maybe Text)

  -- TST-INFRA-006
  describe "TST-INFRA-006: buildOrdersRejectedEvent" $ do
    it "sets eventType to 'orders.rejected'" $ do
      let event = buildOrdersRejectedEvent fixedEventIdentifier fixedTime rejectedPayload
          eventTypeValue = (event :: CloudEvent OrdersRejectedEventPayload).eventType
      eventTypeValue `shouldBe` ("orders.rejected" :: Text)

    it "sets schemaVersion to '1.0.0'" $ do
      let event = buildOrdersRejectedEvent fixedEventIdentifier fixedTime rejectedPayload
          schemaVersionValue = (event :: CloudEvent OrdersRejectedEventPayload).schemaVersion
      schemaVersionValue `shouldBe` ("1.0.0" :: Text)

    it "sets payload.decision to 'rejected'" $ do
      let event = buildOrdersRejectedEvent fixedEventIdentifier fixedTime rejectedPayload
          decisionValue = (event :: CloudEvent OrdersRejectedEventPayload).payload.decision
      decisionValue `shouldBe` ("rejected" :: Text)

    it "sets payload.reasonCode to 'KILL_SWITCH_ENABLED'" $ do
      let event = buildOrdersRejectedEvent fixedEventIdentifier fixedTime rejectedPayload
          reasonCodeValue = (event :: CloudEvent OrdersRejectedEventPayload).payload.reasonCode
      reasonCodeValue `shouldBe` ("KILL_SWITCH_ENABLED" :: Text)

    it "sets trace from payload trace" $ do
      let event = buildOrdersRejectedEvent fixedEventIdentifier fixedTime rejectedPayload
          traceValue = (event :: CloudEvent OrdersRejectedEventPayload).trace
      traceValue `shouldBe` mkULID 200

  -- TST-INFRA-007
  describe "TST-INFRA-007: reasonCodeToWire mappings" $ do
    it "KillSwitchEnabled → 'KILL_SWITCH_ENABLED'" $ do
      reasonCodeToWire KillSwitchEnabled `shouldBe` "KILL_SWITCH_ENABLED"

    it "RiskLimitExceeded → 'RISK_LIMIT_EXCEEDED'" $ do
      reasonCodeToWire RiskLimitExceeded `shouldBe` "RISK_LIMIT_EXCEEDED"

    it "ComplianceRestrictedSymbol → 'COMPLIANCE_RESTRICTED_SYMBOL'" $ do
      reasonCodeToWire ComplianceRestrictedSymbol `shouldBe` "COMPLIANCE_RESTRICTED_SYMBOL"

    it "ComplianceBlackoutActive → 'COMPLIANCE_BLACKOUT_ACTIVE'" $ do
      reasonCodeToWire ComplianceBlackoutActive `shouldBe` "COMPLIANCE_BLACKOUT_ACTIVE"

    it "RiskEvaluationUnavailable → 'RISK_EVALUATION_UNAVAILABLE'" $ do
      reasonCodeToWire RiskEvaluationUnavailable `shouldBe` "RISK_EVALUATION_UNAVAILABLE"
