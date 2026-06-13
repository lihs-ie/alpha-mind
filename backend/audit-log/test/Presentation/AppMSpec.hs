{-# OPTIONS_GHC -fno-hpc #-}

{- | Tests for 'Presentation.AppM'.

 Must-1: Verifies that 'AppM' can invoke 'recordAuditFromSourceEvent'
 (smoke test — requires FIRESTORE_EMULATOR_HOST).

 Must-7: Verifies that 'AuditEventPublisher AppM' calls 'publishCloudEvent'
 on the configured 'PubSubPublisher'.  Uses an 'IORef' counter and a
 custom 'AppEnv' with a mock-style publisher (counter-based).

 Note: The mock publisher is constructed inline only within this test module
 and does NOT appear in production code paths.  The mock cannot use
 'PubSubPublisher' directly for counting because 'accessToken' is @IO Text@;
 instead we use a real 'PubSubPublisher' wired to a local HTTP endpoint that
 always returns a failure, and assert the IORef-based counter increments.
 Since 'AuditEventPublisher' is best-effort, a publish failure still returns
 @()@ without propagating the error.

 For the counter approach we keep it simple: wrap the publisher call in an
 IORef counter by providing a custom @accessToken@ that increments the ref.
-}
module Presentation.AppMSpec (spec) where

import Config.Env (CommonRuntimeEnv (..))
import Data.Aeson (Value (..))
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.AuditLog.AuditIngestion (AuditIngestionIdentifier (..))
import Domain.AuditLog.AuditRecord (AuditRecordIdentifier (..))
import Domain.AuditLog.Specification (RawSourceEvent (..))
import Messaging.PubSub (PubSubPublisher (..))
import Network.HTTP.Client (defaultManagerSettings, newManager)
import Observability.Logging (initLogger)
import Persistence.Firestore (FirestoreContext (..))
import Presentation.AppM (AppEnv (..), runAppM)
import System.Environment (lookupEnv)
import Test.Hspec (Spec, describe, it, pendingWith, shouldBe, shouldSatisfy)
import UseCase.RecordAuditFromSourceEvent (RecordAuditResult (..), recordAuditFromSourceEvent)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2025 6 1) 0

validRawEvent :: RawSourceEvent
validRawEvent =
  RawSourceEvent
    { identifier = Just (mkULID 100)
    , eventType = Just "orders.executed"
    , occurredAt = Just fixedTime
    , trace = Just (mkULID 200)
    , payload = Just (Object mempty)
    }

-- ---------------------------------------------------------------------------
-- AppEnv builder for tests (requires FIRESTORE_EMULATOR_HOST)
-- ---------------------------------------------------------------------------

makeTestAppEnv :: IORef Int -> IO AppEnv
makeTestAppEnv callCounter = do
  httpManager <- newManager defaultManagerSettings
  let runtimeEnv =
        CommonRuntimeEnv
          { port = 8080
          , gcpProjectId = "test-project"
          , serviceName = "audit-log"
          , serviceVersion = "test"
          , revision = Nothing
          , logLevel = "info"
          }
  logEnvironment <- initLogger runtimeEnv
  let firestoreCtx =
        FirestoreContext
          { projectId = "test-project"
          , databaseId = "(default)"
          }
      -- accessToken increments the counter each time it is called.
      -- This lets us verify that publishCloudEvent was invoked.
      publisher =
        PubSubPublisher
          { manager = httpManager
          , projectId = "test-project"
          , baseURL = "http://localhost:19999/"
          , accessToken = do
              modifyIORef' callCounter (+ 1)
              pure "test-token"
          }
  pure
    AppEnv
      { firestoreContext = firestoreCtx
      , logEnv = logEnvironment
      , pubSubPublisher = publisher
      , auditTopicName = "audit-recorded"
      , serviceName = "audit-log"
      }

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "AppM" $ do
    describe "Must-1: recordAuditFromSourceEvent runs in AppM" $ do
      it "returns Recorded for a valid event (requires FIRESTORE_EMULATOR_HOST)" $ do
        maybeEmulatorHost <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulatorHost of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping AppM smoke test"
          Just _ -> do
            counter <- newIORef (0 :: Int)
            appEnv <- makeTestAppEnv counter
            let recordIdentifier = AuditRecordIdentifier (mkULID 1001)
                ingestionIdentifier = AuditIngestionIdentifier (mkULID 1002)
            result <-
              runAppM appEnv $
                recordAuditFromSourceEvent
                  fixedTime
                  recordIdentifier
                  ingestionIdentifier
                  validRawEvent
                  "execution"
            result `shouldBe` Recorded

    describe "Must-7: AuditEventPublisher AppM invokes PubSubPublisher" $ do
      it "accessToken is called when publishAuditRecorded is invoked (best-effort)" $ do
        maybeEmulatorHost <- lookupEnv "FIRESTORE_EMULATOR_HOST"
        case maybeEmulatorHost of
          Nothing ->
            pendingWith "FIRESTORE_EMULATOR_HOST not set — skipping publisher integration test"
          Just _ -> do
            counter <- newIORef (0 :: Int)
            appEnv <- makeTestAppEnv counter
            -- Use a fresh identifier pair to avoid Duplicate from prior test
            let recordIdentifier = AuditRecordIdentifier (mkULID 2001)
                ingestionIdentifier = AuditIngestionIdentifier (mkULID 2002)
            _ <-
              runAppM appEnv $
                recordAuditFromSourceEvent
                  fixedTime
                  recordIdentifier
                  ingestionIdentifier
                  validRawEvent
                  "execution"
            -- accessToken is called once per publishCloudEvent attempt
            callCount <- readIORef counter
            callCount `shouldSatisfy` (>= 1)
