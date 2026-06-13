module UseCase.RecordAuditFromSourceEventSpec (spec) where

import Data.Aeson (Value (..))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ulidFromInteger)
import Domain.AuditLog (Trace (..))
import Domain.AuditLog.AuditIngestion (
  AuditIngestion,
  AuditIngestionIdentifier (..),
  AuditIngestionRepository (..),
 )
import Domain.AuditLog.AuditRecord (
  AuditArchive,
  AuditArchiveRepository (..),
  AuditRecord,
  AuditRecordIdentifier (..),
  AuditRecordRepository (..),
  PayloadDigest (..),
  PayloadSummaryValue (..),
 )
import Domain.AuditLog.Specification (RawSourceEvent (..))
import Domain.AuditLog.Status qualified as Status
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import UseCase.RecordAuditFromSourceEvent (
  AuditEventPublisher (..),
  RecordAuditResult (..),
  buildPayloadDigest,
  recordAuditFromSourceEvent,
 )

-- ---------------------------------------------------------------------
-- Test fixtures
-- ---------------------------------------------------------------------

mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2025 6 1) 0

recordIdentifier :: AuditRecordIdentifier
recordIdentifier = AuditRecordIdentifier (mkULID 1)

ingestionIdentifier :: AuditIngestionIdentifier
ingestionIdentifier = AuditIngestionIdentifier (mkULID 1)

validRawEvent :: RawSourceEvent
validRawEvent =
  RawSourceEvent
    { identifier = Just (mkULID 100)
    , eventType = Just "orders.executed"
    , occurredAt = Just fixedTime
    , trace = Just (mkULID 200)
    , payload = Just (Object KeyMap.empty)
    }

validRawEventWithPayload :: RawSourceEvent
validRawEventWithPayload =
  RawSourceEvent
    { identifier = validRawEvent.identifier
    , eventType = validRawEvent.eventType
    , occurredAt = validRawEvent.occurredAt
    , trace = validRawEvent.trace
    , payload =
        Just
          ( Object $
              KeyMap.fromList
                [ (Key.fromText "ticker", String "7203")
                , (Key.fromText "quantity", Number 100)
                , (Key.fromText "filled", Bool True)
                ]
          )
    }

invalidRawEvent :: RawSourceEvent
invalidRawEvent =
  RawSourceEvent
    { identifier = Nothing
    , eventType = Nothing
    , occurredAt = Nothing
    , trace = Nothing
    , payload = Nothing
    }

-- ---------------------------------------------------------------------
-- Mock monad via IORef
-- ---------------------------------------------------------------------

data MockState = MockState
  { ingestionStore :: Map.Map Text AuditIngestion
  , recordStore :: Map.Map Text AuditRecord
  , archiveStore :: [AuditArchive]
  , publishedRecords :: [AuditRecord]
  }

newMockState :: IO (IORef MockState)
newMockState =
  newIORef
    MockState
      { ingestionStore = Map.empty
      , recordStore = Map.empty
      , archiveStore = []
      , publishedRecords = []
      }

newtype MockM a = MockM {runMockM :: IORef MockState -> IO a}

instance Functor MockM where
  fmap f (MockM g) = MockM $ \ref -> fmap f (g ref)

instance Applicative MockM where
  pure a = MockM $ \_ -> pure a
  MockM f <*> MockM a = MockM $ \ref -> f ref <*> a ref

instance Monad MockM where
  MockM a >>= f = MockM $ \ref -> do
    val <- a ref
    runMockM (f val) ref

instance AuditIngestionRepository MockM where
  find (AuditIngestionIdentifier ulid) = MockM $ \ref -> do
    state <- readIORef ref
    pure $ Map.lookup (showText ulid) state.ingestionStore
  persist ingestion = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state{ingestionStore = Map.insert (showText ingestion.identifier.value) ingestion state.ingestionStore}
  terminate (AuditIngestionIdentifier ulid) = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state{ingestionStore = Map.delete (showText ulid) state.ingestionStore}

instance AuditRecordRepository MockM where
  find (AuditRecordIdentifier ulid) = MockM $ \ref -> do
    state <- readIORef ref
    pure $ Map.lookup (showText ulid) state.recordStore
  findByEventType _ = pure []
  findByTrace _ = pure []
  search _ = pure []
  persist record = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state{recordStore = Map.insert (showText record.identifier.value) record state.recordStore}
  terminate _ = pure ()

instance AuditArchiveRepository MockM where
  persistArchive archive = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state{archiveStore = archive : state.archiveStore}

instance AuditEventPublisher MockM where
  publishAuditRecorded record = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state{publishedRecords = record : state.publishedRecords}

runWithMock :: IORef MockState -> MockM a -> IO a
runWithMock ref (MockM f) = f ref

showText :: (Show a) => a -> Text
showText = Text.pack . Prelude.show

-- ---------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "UseCase.RecordAuditFromSourceEvent" $ do
    describe "recordAuditFromSourceEvent" $ do
      it "returns SchemaInvalid when required fields are missing" $ do
        ref <- newMockState
        result <-
          runWithMock ref $ recordAuditFromSourceEvent fixedTime recordIdentifier ingestionIdentifier invalidRawEvent "execution"
        result `shouldSatisfy` isSchemaInvalid

      it "records a valid event successfully" $ do
        ref <- newMockState
        result <-
          runWithMock ref $ recordAuditFromSourceEvent fixedTime recordIdentifier ingestionIdentifier validRawEvent "execution"
        result `shouldBe` Recorded

      it "persists audit record to the store" $ do
        ref <- newMockState
        _ <-
          runWithMock ref $ recordAuditFromSourceEvent fixedTime recordIdentifier ingestionIdentifier validRawEvent "execution"
        state <- readIORef ref
        Map.size state.recordStore `shouldBe` 1

      it "persists ingestion to the store" $ do
        ref <- newMockState
        _ <-
          runWithMock ref $ recordAuditFromSourceEvent fixedTime recordIdentifier ingestionIdentifier validRawEvent "execution"
        state <- readIORef ref
        Map.size state.ingestionStore `shouldBe` 1

      it "archives to Cloud Logging" $ do
        ref <- newMockState
        _ <-
          runWithMock ref $ recordAuditFromSourceEvent fixedTime recordIdentifier ingestionIdentifier validRawEvent "execution"
        state <- readIORef ref
        length state.archiveStore `shouldBe` 1

      it "publishes audit.recorded event" $ do
        ref <- newMockState
        _ <-
          runWithMock ref $ recordAuditFromSourceEvent fixedTime recordIdentifier ingestionIdentifier validRawEvent "execution"
        state <- readIORef ref
        length state.publishedRecords `shouldBe` 1

      it "records the audit record in Recorded status" $ do
        ref <- newMockState
        _ <-
          runWithMock ref $ recordAuditFromSourceEvent fixedTime recordIdentifier ingestionIdentifier validRawEvent "execution"
        state <- readIORef ref
        let [record] = Map.elems state.recordStore
        record.status `shouldBe` Status.Recorded

      it "marks ingestion as processed" $ do
        ref <- newMockState
        _ <-
          runWithMock ref $ recordAuditFromSourceEvent fixedTime recordIdentifier ingestionIdentifier validRawEvent "execution"
        state <- readIORef ref
        let [ingestion] = Map.elems state.ingestionStore
        ingestion.processed `shouldBe` True

      it "returns Duplicate for already processed ingestion" $ do
        ref <- newMockState
        _ <-
          runWithMock ref $ recordAuditFromSourceEvent fixedTime recordIdentifier ingestionIdentifier validRawEvent "execution"
        -- 2回目は Duplicate
        result <-
          runWithMock ref $
            recordAuditFromSourceEvent fixedTime (AuditRecordIdentifier (mkULID 2)) ingestionIdentifier validRawEvent "execution"
        result `shouldBe` Duplicate

      it "returns Duplicate without creating additional records" $ do
        ref <- newMockState
        _ <-
          runWithMock ref $ recordAuditFromSourceEvent fixedTime recordIdentifier ingestionIdentifier validRawEvent "execution"
        _ <-
          runWithMock ref $
            recordAuditFromSourceEvent fixedTime (AuditRecordIdentifier (mkULID 2)) ingestionIdentifier validRawEvent "execution"
        state <- readIORef ref
        Map.size state.recordStore `shouldBe` 1

      it "records event with payload summary from source event" $ do
        ref <- newMockState
        _ <-
          runWithMock ref $
            recordAuditFromSourceEvent fixedTime recordIdentifier ingestionIdentifier validRawEventWithPayload "execution"
        state <- readIORef ref
        let [record] = Map.elems state.recordStore
        record.payloadSummary `shouldSatisfy` (/= Nothing)

      it "returns SchemaInvalid when only some fields are missing" $ do
        ref <- newMockState
        let partialEvent =
              RawSourceEvent
                { identifier = validRawEvent.identifier
                , eventType = validRawEvent.eventType
                , occurredAt = validRawEvent.occurredAt
                , trace = Nothing
                , payload = validRawEvent.payload
                }
        result <-
          runWithMock ref $ recordAuditFromSourceEvent fixedTime recordIdentifier ingestionIdentifier partialEvent "execution"
        result `shouldSatisfy` isSchemaInvalid

    describe "buildPayloadDigest" $ do
      it "extracts top-level keys from JSON object" $ do
        let payload =
              Object $
                KeyMap.fromList
                  [ (Key.fromText "ticker", String "7203")
                  , (Key.fromText "quantity", Number 100)
                  ]
            PayloadDigest{fieldCount = fc, topLevelKeys = keys} = buildPayloadDigest payload
        fc `shouldBe` 2
        length keys `shouldBe` 2

      it "extracts string values to summary" $ do
        let payload =
              Object $
                KeyMap.fromList
                  [(Key.fromText "ticker", String "7203")]
            PayloadDigest{summary = s} = buildPayloadDigest payload
        Map.lookup ("ticker" :: Text) s `shouldBe` Just (SummaryString "7203")

      it "extracts number values to summary" $ do
        let payload =
              Object $
                KeyMap.fromList
                  [(Key.fromText "quantity", Number 100)]
            PayloadDigest{summary = s} = buildPayloadDigest payload
        Map.lookup ("quantity" :: Text) s `shouldBe` Just (SummaryNumber 100.0)

      it "extracts boolean values to summary" $ do
        let payload =
              Object $
                KeyMap.fromList
                  [(Key.fromText "filled", Bool True)]
            PayloadDigest{summary = s} = buildPayloadDigest payload
        Map.lookup ("filled" :: Text) s `shouldBe` Just (SummaryBool True)

      it "skips non-primitive values in summary" $ do
        let payload =
              Object $
                KeyMap.fromList
                  [(Key.fromText "nested", Object KeyMap.empty)]
            PayloadDigest{fieldCount = fc, summary = s} = buildPayloadDigest payload
        fc `shouldBe` 1
        Map.size s `shouldBe` 0

      it "returns empty digest for non-object values" $ do
        let PayloadDigest{fieldCount = fc, topLevelKeys = keys, summary = s} = buildPayloadDigest Null
        fc `shouldBe` 0
        keys `shouldBe` ([] :: [Text])
        Map.size s `shouldBe` 0

      it "returns empty digest for Array value" $ do
        let PayloadDigest{fieldCount = fc} = buildPayloadDigest (Array mempty)
        fc `shouldBe` 0

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

isSchemaInvalid :: RecordAuditResult -> Bool
isSchemaInvalid (SchemaInvalid _) = True
isSchemaInvalid _ = False
