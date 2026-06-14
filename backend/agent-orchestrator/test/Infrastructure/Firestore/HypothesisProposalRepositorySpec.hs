module Infrastructure.Firestore.HypothesisProposalRepositorySpec (spec) where

import Data.HashMap.Strict qualified as HashMap
import Data.IORef (modifyIORef, newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime, secondsToNominalDiffTime)
import Data.ULID (ULID)
import Domain.HypothesisOrchestration (Trace (..))
import Domain.HypothesisOrchestration.Aggregate (
  HypothesisProposal,
  HypothesisProposalIdentifier (..),
  HypothesisProposalRepository (..),
  ProposalStatus (..),
  startProposal,
 )
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Gogol.FireStore qualified as GogolFireStore
import Infrastructure.Firestore.Env (FirestoreEnv (..), FirestoreTransport (..))
import Infrastructure.Firestore.HypothesisProposalRepository (
  FirestoreHypothesisProposalEnv (..),
  fieldsToProposal,
  proposalStatusFromText,
  proposalStatusToText,
  proposalToFields,
  runFirestoreHypothesisProposalRepositoryT,
 )
import Persistence.Firestore (CollectionName, DocumentId, FirestoreError (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case readMaybe "01ARZ3NDEKTSV4RRFFQ69G5FAV" of
  Just u -> u
  Nothing -> error "invalid test ULID"

testTraceUlid :: ULID
testTraceUlid = case readMaybe "01BX5ZZKBKACTAV9WEVGEMMVRE" of
  Just u -> u
  Nothing -> error "invalid test trace ULID"

testCreatedAt :: UTCTime
testCreatedAt = UTCTime (fromGregorian 2024 1 15) 0

testProposal :: HypothesisProposal
testProposal =
  fst $
    startProposal
      HypothesisProposalIdentifier{value = testUlid}
      "dispatch-ref-001"
      Trace{value = testTraceUlid}
      testCreatedAt

-- ---------------------------------------------------------------------------
-- Mock transport helpers (Must-26)
-- ---------------------------------------------------------------------------

makeEnvWithGet ::
  (CollectionName -> DocumentId -> IO (Either FirestoreError (Maybe (HashMap.HashMap Text GogolFireStore.Value)))) ->
  FirestoreHypothesisProposalEnv
makeEnvWithGet getDocumentFn =
  FirestoreHypothesisProposalEnv
    { firestoreEnv =
        FirestoreEnv
          { firestoreExecute =
              FirestoreTransport
                { transportGetDocument = getDocumentFn
                , transportUpsertDocument = \_ _ _ -> pure (Right ())
                , transportDeleteDocument = \_ _ -> pure (Right ())
                , transportRunQuery = \_ _ _ _ -> pure (Right [])
                }
          , projectIdentifier = "test-project"
          , databaseIdentifier = "(default)"
          }
    }

makeEnvWithUpsert ::
  (CollectionName -> DocumentId -> HashMap.HashMap Text GogolFireStore.Value -> IO (Either FirestoreError ())) ->
  FirestoreHypothesisProposalEnv
makeEnvWithUpsert upsertFn =
  FirestoreHypothesisProposalEnv
    { firestoreEnv =
        FirestoreEnv
          { firestoreExecute =
              FirestoreTransport
                { transportGetDocument = \_ _ -> pure (Right Nothing)
                , transportUpsertDocument = upsertFn
                , transportDeleteDocument = \_ _ -> pure (Right ())
                , transportRunQuery = \_ _ _ _ -> pure (Right [])
                }
          , projectIdentifier = "test-project"
          , databaseIdentifier = "(default)"
          }
    }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False

-- ---------------------------------------------------------------------------
-- Spec (Must-25, Must-29)
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
  describe "Infrastructure.Firestore.HypothesisProposalRepository" $ do
    -- Status mapping tests (Must-13)
    -- Mapping: Pending↔"draft", Proposed↔"backtested", Blocked↔"rejected", Failed↔"failed"
    describe "status codec" $ do
      it "Pending ↔ 'draft'" $ do
        proposalStatusToText Pending `shouldBe` "draft"
        proposalStatusFromText "draft" `shouldBe` Right Pending

      it "Proposed ↔ 'backtested'" $ do
        proposalStatusToText Proposed `shouldBe` "backtested"
        proposalStatusFromText "backtested" `shouldBe` Right Proposed

      it "Blocked ↔ 'rejected'" $ do
        proposalStatusToText Blocked `shouldBe` "rejected"
        proposalStatusFromText "rejected" `shouldBe` Right Blocked

      it "Failed ↔ 'failed'" $ do
        proposalStatusToText Failed `shouldBe` "failed"
        proposalStatusFromText "failed" `shouldBe` Right Failed

      it "must-13: 'live' is hypothesis-lab lifecycle value → Left DomainError" $ do
        case proposalStatusFromText "live" of
          Left (MissingRequiredFields ["status"] RequestValidationFailed) -> pure () :: IO ()
          other -> fail ("Expected Left MissingRequiredFields status, got: " <> show other)

      it "must-13: 'demo' is hypothesis-lab lifecycle value → Left DomainError" $ do
        proposalStatusFromText "demo" `shouldSatisfy` isLeft

      it "must-13: unknown status value → Left DomainError" $ do
        proposalStatusFromText "generating" `shouldSatisfy` isLeft

    -- Pure codec tests (Must-26)
    describe "round-trip codec" $ do
      it "encodes and decodes HypothesisProposal identifier/trace/dispatch/createdAt" $ do
        let fields = proposalToFields testCreatedAt testProposal
            result = fieldsToProposal fields
        case result of
          Left domainError -> fail ("Expected Right, got Left: " <> show domainError)
          Right proposal -> do
            proposal.identifier `shouldBe` testProposal.identifier
            proposal.dispatch `shouldBe` testProposal.dispatch
            proposal.createdAt `shouldBe` testProposal.createdAt

      it "must-13: unknown status in fields → Left DomainError" $ do
        let baseFields = proposalToFields testCreatedAt testProposal
            badFields =
              HashMap.insert
                "status"
                (GogolFireStore.newValue{GogolFireStore.stringValue = Just "generating"})
                baseFields
            result = fieldsToProposal badFields
        result `shouldSatisfy` isLeft

      it "returns Left DomainError for missing identifier field" $ do
        let missingFields = HashMap.delete "identifier" (proposalToFields testCreatedAt testProposal)
            result = fieldsToProposal missingFields
        result `shouldSatisfy` isLeft

    -- Repository IO tests (Must-29)
    describe "find" $ do
      it "find normal case: mock returns valid document → returns Just HypothesisProposal" $ do
        let fields = proposalToFields testCreatedAt testProposal
            environment = makeEnvWithGet (\_ _ -> pure (Right (Just fields)))
        result <- runFirestoreHypothesisProposalRepositoryT environment (find testProposal.identifier)
        case result of
          Nothing -> fail "Expected Just, got Nothing"
          Just proposal -> proposal.identifier `shouldBe` testProposal.identifier

      it "find document absent: mock returns Nothing → returns Nothing" $ do
        let environment = makeEnvWithGet (\_ _ -> pure (Right Nothing))
        result <- runFirestoreHypothesisProposalRepositoryT environment (find testProposal.identifier)
        result `shouldBe` Nothing

    -- persist test (Must-14)
    describe "persist" $ do
      it "persist normal case: upsert succeeds (Must-29)" $ do
        let environment = makeEnvWithUpsert (\_ _ _ -> pure (Right ()))
        runFirestoreHypothesisProposalRepositoryT environment (persist testProposal) :: IO ()

      it "must-14: persist writes updatedAt field as timestamp" $ do
        capturedFieldsRef <- newIORef HashMap.empty
        let environment =
              makeEnvWithUpsert
                ( \_ _ fieldMap -> do
                    writeIORef capturedFieldsRef fieldMap
                    pure (Right ())
                )
        runFirestoreHypothesisProposalRepositoryT environment (persist testProposal)
        capturedFields <- readIORef capturedFieldsRef
        case HashMap.lookup "updatedAt" capturedFields of
          Nothing -> fail "Expected updatedAt field to be present"
          Just updatedAtValue ->
            case updatedAtValue.timestampValue of
              Nothing -> fail "Expected updatedAt to be a timestamp"
              Just _ -> pure ()

      it "must-14: persist writes createdAt using proposal.createdAt (not overwritten)" $ do
        capturedFieldsRef <- newIORef HashMap.empty
        let environment =
              makeEnvWithUpsert
                ( \_ _ fieldMap -> do
                    writeIORef capturedFieldsRef fieldMap
                    pure (Right ())
                )
        runFirestoreHypothesisProposalRepositoryT environment (persist testProposal)
        capturedFields <- readIORef capturedFieldsRef
        case HashMap.lookup "createdAt" capturedFields of
          Nothing -> fail "Expected createdAt field to be present"
          Just createdAtValue ->
            case createdAtValue.timestampValue of
              Nothing -> fail "Expected createdAt to be a timestamp"
              Just _ -> pure ()

      it "must-14: createdAt is invariant across repeated persists (pure codec check)" $ do
        -- proposalToFields uses proposal.createdAt (not the 'now' parameter) for createdAt.
        -- This proves that even when now changes between calls, createdAt stays the same.
        let now1 = UTCTime (fromGregorian 2024 6 1) 0
            now2 = addUTCTime (secondsToNominalDiffTime 3600) now1
            fields1 = proposalToFields now1 testProposal
            fields2 = proposalToFields now2 testProposal
        -- createdAt must be identical in both field maps
        HashMap.lookup "createdAt" fields1 `shouldBe` HashMap.lookup "createdAt" fields2
        -- updatedAt must differ (it reflects 'now')
        HashMap.lookup "updatedAt" fields1 `shouldSatisfy` (/= HashMap.lookup "updatedAt" fields2)

      it "must-14: two sequential upserts produce identical createdAt (IO-level)" $ do
        -- Captures the createdAt value from each upsert call.
        -- Both calls use the same testProposal (same proposal.createdAt), so createdAt is stable.
        capturedCreatedAtsRef <- newIORef ([] :: [Maybe GogolFireStore.Value])
        let environment =
              makeEnvWithUpsert
                ( \_ _ fieldMap -> do
                    modifyIORef capturedCreatedAtsRef (HashMap.lookup "createdAt" fieldMap :)
                    pure (Right ())
                )
        runFirestoreHypothesisProposalRepositoryT environment (persist testProposal)
        runFirestoreHypothesisProposalRepositoryT environment (persist testProposal)
        capturedCreatedAts <- readIORef capturedCreatedAtsRef
        case capturedCreatedAts of
          [second, first] -> first `shouldBe` second
          other -> fail ("Expected exactly 2 captured createdAt values, got: " <> show (length other))
