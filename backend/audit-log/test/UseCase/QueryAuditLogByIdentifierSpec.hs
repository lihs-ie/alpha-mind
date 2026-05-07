module UseCase.QueryAuditLogByIdentifierSpec (spec) where

import Data.Aeson (Value (..))
import Data.Either (isLeft, isRight)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ulidFromInteger)
import Domain.AuditLog (Trace (..))
import Domain.AuditLog.AuditRecord (
  AuditRecord,
  AuditRecordIdentifier (..),
  AuditRecordRepository (..),
  SearchCriteria,
  SourceEventIdentifier (..),
  SourceEventSnapshot (..),
  acceptSourceEvent,
  markRecorded,
  normalizeReason,
 )
import Domain.AuditLog.ReasonSource (ReasonSource (..))
import Domain.AuditLog.Result qualified as Result
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldSatisfy)
import UseCase.QueryAuditLogByIdentifier (
  AuditDetail (..),
  QueryAuditLogError (..),
  queryAuditLogByIdentifier,
 )

-- ---------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------

mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2025 1 1) 0

testRecord :: AuditRecord
testRecord =
  let snapshot =
        SourceEventSnapshot
          { identifier = SourceEventIdentifier (mkULID 50)
          , eventType = "orders.executed"
          , occurredAt = fixedTime
          , trace = Trace (mkULID 10)
          , payload = Null
          }
      (pending, _) =
        acceptSourceEvent
          (AuditRecordIdentifier (mkULID 1))
          snapshot
          "execution"
          Result.Success
   in case normalizeReason (Just "manual") FromReason pending of
        Left err -> error ("normalizeReason failed: " <> show err)
        Right normalized ->
          case markRecorded fixedTime normalized of
            Left err -> error ("markRecorded failed: " <> show err)
            Right (recorded, _) -> recorded

-- ---------------------------------------------------------------------
-- Mock monad
-- ---------------------------------------------------------------------

newtype MockRepo a = MockRepo {runMock :: Maybe AuditRecord -> a}

instance Functor MockRepo where
  fmap f (MockRepo g) = MockRepo (f . g)

instance Applicative MockRepo where
  pure a = MockRepo (const a)
  MockRepo f <*> MockRepo a = MockRepo $ \r -> f r (a r)

instance Monad MockRepo where
  MockRepo a >>= f = MockRepo $ \r -> runMock (f (a r)) r

instance AuditRecordRepository MockRepo where
  find _ = MockRepo id
  findByEventType _ = pure []
  findByTrace _ = pure []
  search _ = pure []
  persist _ = pure ()
  terminate _ = pure ()

-- ---------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "UseCase.QueryAuditLogByIdentifier" $ do
    describe "queryAuditLogByIdentifier" $ do
      it "returns AuditDetail when record exists" $ do
        let result = runMock (queryAuditLogByIdentifier (AuditRecordIdentifier (mkULID 1))) (Just testRecord)
        result `shouldSatisfy` isRight

      it "projects all fields correctly" $ do
        let result = runMock (queryAuditLogByIdentifier (AuditRecordIdentifier (mkULID 1))) (Just testRecord)
        case result of
          Left _ -> expectationFailure "expected Right but got Left"
          Right detail -> do
            detail.identifier `shouldBe` testRecord.identifier
            detail.occurredAt `shouldBe` testRecord.occurredAt
            detail.eventType `shouldBe` testRecord.eventType
            detail.service `shouldBe` testRecord.service
            detail.result `shouldBe` testRecord.result
            detail.trace `shouldBe` testRecord.trace
            detail.reason `shouldBe` Just "manual"

      it "includes source event payload in detail" $ do
        let result = runMock (queryAuditLogByIdentifier (AuditRecordIdentifier (mkULID 1))) (Just testRecord)
        case result of
          Left _ -> expectationFailure "expected Right but got Left"
          Right detail -> detail.payload `shouldBe` Just Null

      it "returns AuditLogNotFound when record does not exist" $ do
        let targetIdentifier = AuditRecordIdentifier (mkULID 999)
            result = runMock (queryAuditLogByIdentifier targetIdentifier) Nothing
        result `shouldSatisfy` isLeft

      it "returns the correct identifier in the error" $ do
        let targetIdentifier = AuditRecordIdentifier (mkULID 999)
            result = runMock (queryAuditLogByIdentifier targetIdentifier) Nothing
        case result of
          Right _ -> expectationFailure "expected Left but got Right"
          Left (AuditLogNotFound errorIdentifier) ->
            errorIdentifier `shouldBe` targetIdentifier
