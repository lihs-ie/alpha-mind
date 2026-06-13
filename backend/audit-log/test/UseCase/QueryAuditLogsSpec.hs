module UseCase.QueryAuditLogsSpec (spec) where

import Data.Aeson (Value (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ulidFromInteger)
import Domain.AuditLog (EventType, Trace (..))
import Domain.AuditLog.AuditRecord (
  AuditRecord,
  AuditRecordIdentifier (..),
  AuditRecordRepository (..),
  SearchCriteria (..),
  SourceEventIdentifier (..),
  SourceEventSnapshot (..),
  acceptSourceEvent,
  markRecorded,
 )
import Domain.AuditLog.Result qualified as Result
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import UseCase.QueryAuditLogs (
  AuditListResponse (..),
  AuditQueryInput (..),
  AuditSummary (..),
  queryAuditLogs,
  toAuditSummary,
 )

-- ---------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------

mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2025 1 1) 0

mkTestRecord :: Integer -> AuditRecord
mkTestRecord n =
  let snapshot =
        SourceEventSnapshot
          { identifier = SourceEventIdentifier (mkULID (n + 100))
          , eventType = "orders.executed"
          , occurredAt = fixedTime
          , trace = Trace (mkULID (n + 1000))
          , payload = Null
          }
      (pending, _) =
        acceptSourceEvent
          (AuditRecordIdentifier (mkULID n))
          snapshot
          "execution"
          Result.Success
   in case markRecorded fixedTime pending of
        Left err -> error ("markRecorded failed: " <> show err)
        Right (recorded, _) -> recorded

-- ---------------------------------------------------------------------
-- Mock monad
-- ---------------------------------------------------------------------

newtype MockRecordRepo a = MockRecordRepo {runMock :: [AuditRecord] -> a}

instance Functor MockRecordRepo where
  fmap f (MockRecordRepo g) = MockRecordRepo (f . g)

instance Applicative MockRecordRepo where
  pure a = MockRecordRepo (const a)
  MockRecordRepo f <*> MockRecordRepo a = MockRecordRepo $ \records -> f records (a records)

instance Monad MockRecordRepo where
  MockRecordRepo a >>= f = MockRecordRepo $ \records -> runMock (f (a records)) records

instance AuditRecordRepository MockRecordRepo where
  find identifier = MockRecordRepo $ \records ->
    case filter (\r -> r.identifier == identifier) records of
      (r : _) -> Just r
      [] -> Nothing
  findByEventType _ = pure []
  findByTrace _ = pure []
  search criteria = MockRecordRepo $ \records ->
    let filtered = applyFilters criteria records
        limited = case criteria.limitCount of
          Just n -> take n filtered
          Nothing -> filtered
     in limited
  persist _ = pure ()
  terminate _ = pure ()

applyFilters :: SearchCriteria -> [AuditRecord] -> [AuditRecord]
applyFilters criteria =
  filter $ \record ->
    maybe True (== record.eventType) criteria.eventTypeFilter
      && maybe True (== record.trace) criteria.traceFilter

emptyInput :: AuditQueryInput
emptyInput =
  AuditQueryInput
    { traceFilter = Nothing
    , eventTypeFilter = Nothing
    , fromDate = Nothing
    , toDate = Nothing
    , limitCount = 50
    , cursor = Nothing
    }

mkInput :: Int -> Maybe EventType -> Maybe Trace -> AuditQueryInput
mkInput limit eventType traceValue =
  AuditQueryInput
    { traceFilter = traceValue
    , eventTypeFilter = eventType
    , fromDate = Nothing
    , toDate = Nothing
    , limitCount = limit
    , cursor = Nothing
    }

-- ---------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "UseCase.QueryAuditLogs" $ do
    describe "queryAuditLogs" $ do
      it "returns empty list when no records exist" $ do
        let result = runMock (queryAuditLogs emptyInput) []
        result.items `shouldBe` []
        result.nextCursor `shouldBe` Nothing

      it "returns all records when count is less than limit" $ do
        let records = map mkTestRecord [1 .. 3]
            result = runMock (queryAuditLogs emptyInput) records
        length result.items `shouldBe` 3
        result.nextCursor `shouldBe` Nothing

      it "returns nextCursor when records equal limit" $ do
        let records = map mkTestRecord [1 .. 5]
            input = mkInput 5 Nothing Nothing
            result = runMock (queryAuditLogs input) records
        length result.items `shouldBe` 5
        result.nextCursor `shouldSatisfy` (/= Nothing)

      it "caps limit at 100" $ do
        let records = map mkTestRecord [1 .. 5]
            input = mkInput 200 Nothing Nothing
            result = runMock (queryAuditLogs input) records
        length result.items `shouldBe` 5
        result.nextCursor `shouldBe` Nothing

      it "enforces minimum limit of 1" $ do
        let records = map mkTestRecord [1 .. 3]
            input = mkInput 0 Nothing Nothing
            result = runMock (queryAuditLogs input) records
        length result.items `shouldSatisfy` (>= 1)

      it "filters by eventType" $ do
        let records = map mkTestRecord [1 .. 3]
            input = mkInput 50 (Just "orders.executed") Nothing
            result = runMock (queryAuditLogs input) records
        length result.items `shouldBe` 3

      it "filters by trace" $ do
        let records = map mkTestRecord [1 .. 3]
            targetTrace = Trace (mkULID 1001)
            input = mkInput 50 Nothing (Just targetTrace)
            result = runMock (queryAuditLogs input) records
        length result.items `shouldBe` 1

    describe "toAuditSummary" $ do
      it "projects AuditRecord to AuditSummary" $ do
        let record = mkTestRecord 1
            summary = toAuditSummary record
        summary.identifier `shouldBe` record.identifier
        summary.occurredAt `shouldBe` record.occurredAt
        summary.eventType `shouldBe` record.eventType
        summary.service `shouldBe` record.service
        summary.result `shouldBe` record.result
        summary.trace `shouldBe` record.trace
