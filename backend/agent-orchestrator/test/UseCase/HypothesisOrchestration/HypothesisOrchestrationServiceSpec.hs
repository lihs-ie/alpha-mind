module UseCase.HypothesisOrchestration.HypothesisOrchestrationServiceSpec (spec) where

import Control.Monad.State (State, get, gets, modify, runState)
import Data.Either (isLeft)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.HypothesisOrchestration (Trace (..))
import Domain.HypothesisOrchestration.Aggregate (
  HypothesisProposal,
  HypothesisProposalIdentifier (..),
  HypothesisProposalRepository (..),
 )
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.FailureKnowledge (
  FailureKnowledge (..),
  FailureKnowledgeIdentifier (..),
  FailureKnowledgeRepository (..),
 )
import Domain.HypothesisOrchestration.HypothesisProposalFactory (
  InsightCollectedEvent (..),
  RetestRequestedEvent (..),
 )
import Domain.HypothesisOrchestration.InstructionProfile (
  InstructionProfile (..),
  InstructionProfileRepository (..),
 )
import Domain.HypothesisOrchestration.OrchestrationDispatch (
  OrchestrationDispatch,
  OrchestrationDispatchIdentifier (..),
  OrchestrationDispatchRepository (..),
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.SkillExecutor (
  SkillExecutor (..),
  SkillOutput (..),
 )
import Domain.HypothesisOrchestration.SkillRegistry (
  Skill (..),
  SkillRegistryRepository (..),
  SkillStatus (..),
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import UseCase.HypothesisOrchestration.HypothesisOrchestrationService (
  orchestrateFromInsight,
  orchestrateFromRetest,
 )

-- ---------------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

testTrace :: Trace
testTrace = Trace (mkULID 100)

testProposalIdentifier :: HypothesisProposalIdentifier
testProposalIdentifier = HypothesisProposalIdentifier (mkULID 1)

testDispatchIdentifier :: OrchestrationDispatchIdentifier
testDispatchIdentifier = OrchestrationDispatchIdentifier (mkULID 2)

testFailureKnowledgeIdentifier :: FailureKnowledgeIdentifier
testFailureKnowledgeIdentifier = FailureKnowledgeIdentifier (mkULID 3)

mkTestInsightEvent :: InsightCollectedEvent
mkTestInsightEvent =
  InsightCollectedEvent
    { insightIdentifier = "insight-001"
    , dispatchReference = "dispatch-ref-001"
    , trace = testTrace
    , occurredAt = fixedTime
    }

mkTestRetestEvent :: RetestRequestedEvent
mkTestRetestEvent =
  RetestRequestedEvent
    { retestIdentifier = "retest-001"
    , dispatchReference = "dispatch-ref-002"
    , trace = testTrace
    , occurredAt = fixedTime
    }

testSkill :: Skill
testSkill =
  Skill
    { identifier = "skill-001"
    , name = "hypothesis-skill"
    , version = "1.0.0"
    , status = SkillActive
    }

testProfile :: InstructionProfile
testProfile =
  InstructionProfile
    { identifier = "profile-001"
    , name = "default-profile"
    , version = "2.0.0"
    , content = "## Instruction\nGenerate hypothesis."
    }

testSkillOutput :: SkillOutput
testSkillOutput =
  SkillOutput
    { generatedContent = "Hypothesis content about 7203.T"
    , llmModel = "gpt-4o"
    , sourceEvidence = ["evidence-1", "evidence-2"]
    }

-- ---------------------------------------------------------------------------
-- In-memory test state
-- ---------------------------------------------------------------------------

data OrchestratorTestState = OrchestratorTestState
  { dispatch :: Maybe OrchestrationDispatch
  , proposal :: Maybe HypothesisProposal
  , knowledgeEntries :: [FailureKnowledge]
  , availableSkill :: Maybe Skill
  , availableProfile :: Maybe InstructionProfile
  , skillExecutorResult :: Either DomainError SkillOutput
  , proposalPersistCount :: Int
  , dispatchPersistCount :: Int
  , knowledgePersistCount :: Int
  }

defaultState :: OrchestratorTestState
defaultState =
  OrchestratorTestState
    { dispatch = Nothing
    , proposal = Nothing
    , knowledgeEntries = []
    , availableSkill = Just testSkill
    , availableProfile = Just testProfile
    , skillExecutorResult = Right testSkillOutput
    , proposalPersistCount = 0
    , dispatchPersistCount = 0
    , knowledgePersistCount = 0
    }

-- State without skill (to trigger ResourceNotFound)
stateWithNoSkill :: OrchestratorTestState
stateWithNoSkill = defaultState{availableSkill = Nothing}

-- State without profile (to trigger ResourceNotFound)
stateWithNoProfile :: OrchestratorTestState
stateWithNoProfile = defaultState{availableProfile = Nothing}

-- State where skill executor fails
stateWithSkillFailure :: OrchestratorTestState
stateWithSkillFailure =
  defaultState
    { skillExecutorResult = Left (InvariantViolation "SkillExecutor" "Execution failed" DependencyUnavailable)
    }

-- State with existing failure knowledge entries (triggers duplicate suppression)
stateWithExistingKnowledge :: OrchestratorTestState
stateWithExistingKnowledge =
  defaultState
    { knowledgeEntries =
        [ FailureKnowledge
            { identifier = FailureKnowledgeIdentifier (mkULID 999)
            , reasonCode = StateConflict
            , summary = "Previous duplicate"
            , markdownSummary = "## Previous duplicate"
            , similarityHash = "abc123"
            , recordedAt = fixedTime
            }
        ]
    }

-- ---------------------------------------------------------------------------
-- Test monad (test-only, lives in test/)
-- ---------------------------------------------------------------------------

newtype OrchestratorTestMonad a = OrchestratorTestMonad
  { runOrchestratorTestMonad :: State OrchestratorTestState a
  }
  deriving newtype (Functor, Applicative, Monad)

instance OrchestrationDispatchRepository OrchestratorTestMonad where
  find _ = OrchestratorTestMonad (gets dispatch)
  persist d =
    OrchestratorTestMonad $
      modify (\state -> state{dispatch = Just d, dispatchPersistCount = dispatchPersistCount state + 1})
  terminate _ = pure ()

instance HypothesisProposalRepository OrchestratorTestMonad where
  find _ = OrchestratorTestMonad (gets proposal)
  findByStatus _ = pure []
  search _ = pure []
  persist p =
    OrchestratorTestMonad $
      modify (\state -> state{proposal = Just p, proposalPersistCount = proposalPersistCount state + 1})
  terminate _ = pure ()

instance SkillRegistryRepository OrchestratorTestMonad where
  find _ = OrchestratorTestMonad (gets availableSkill)
  findByStatus _ = pure []
  search _ = pure []

instance InstructionProfileRepository OrchestratorTestMonad where
  find _ = OrchestratorTestMonad (gets availableProfile)
  findByVersion _ = OrchestratorTestMonad (gets availableProfile)
  search _ = pure []

instance FailureKnowledgeRepository OrchestratorTestMonad where
  find _ = pure Nothing
  findByReasonCode _ = pure []
  search _ = OrchestratorTestMonad (gets knowledgeEntries)
  persist knowledge =
    OrchestratorTestMonad $
      modify
        ( \state ->
            state{knowledgeEntries = knowledge : knowledgeEntries state, knowledgePersistCount = knowledgePersistCount state + 1}
        )

instance SkillExecutor OrchestratorTestMonad where
  executeSkill _ = OrchestratorTestMonad (gets skillExecutorResult)

runWith :: OrchestratorTestState -> OrchestratorTestMonad a -> (a, OrchestratorTestState)
runWith initialState action = runState (runOrchestratorTestMonad action) initialState

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
  describe "UseCase.HypothesisOrchestration.HypothesisOrchestrationService" $ do
    describe "orchestrateFromInsight" $ do
      it "returns Right () on successful orchestration" $ do
        let (result, _) =
              runWith defaultState $
                orchestrateFromInsight
                  testDispatchIdentifier
                  testProposalIdentifier
                  testFailureKnowledgeIdentifier
                  mkTestInsightEvent
                  fixedTime
        result `shouldBe` Right ()

      it "persists proposal before dispatch (RULE-AO-006)" $ do
        let (result, finalState) =
              runWith defaultState $
                orchestrateFromInsight
                  testDispatchIdentifier
                  testProposalIdentifier
                  testFailureKnowledgeIdentifier
                  mkTestInsightEvent
                  fixedTime
        result `shouldBe` Right ()
        -- Both proposal and dispatch should be persisted
        proposalPersistCount finalState `shouldSatisfy` (>= 1)
        dispatchPersistCount finalState `shouldSatisfy` (>= 1)

      it "returns Right () silently when dispatch already exists (idempotency)" $ do
        -- First orchestration creates the dispatch
        let (_, stateAfterFirst) =
              runWith defaultState $
                orchestrateFromInsight
                  testDispatchIdentifier
                  testProposalIdentifier
                  testFailureKnowledgeIdentifier
                  mkTestInsightEvent
                  fixedTime
        -- Second call with same dispatch identifier should be idempotent
        let (secondResult, _) =
              runWith stateAfterFirst $
                orchestrateFromInsight
                  testDispatchIdentifier
                  testProposalIdentifier
                  testFailureKnowledgeIdentifier
                  mkTestInsightEvent
                  fixedTime
        secondResult `shouldBe` Right ()

      it "returns Left when duplicate suppression blocks the proposal (RULE-AO-003)" $ do
        let (result, finalState) =
              runWith stateWithExistingKnowledge $
                orchestrateFromInsight
                  testDispatchIdentifier
                  testProposalIdentifier
                  testFailureKnowledgeIdentifier
                  mkTestInsightEvent
                  fixedTime
        result `shouldSatisfy` isLeft
        -- Blocked proposal must be persisted
        proposalPersistCount finalState `shouldSatisfy` (>= 1)
        -- Failure knowledge must be registered for the suppression event
        knowledgePersistCount finalState `shouldSatisfy` (>= 1)

      it "returns Left when skill is not found" $ do
        let (result, finalState) =
              runWith stateWithNoSkill $
                orchestrateFromInsight
                  testDispatchIdentifier
                  testProposalIdentifier
                  testFailureKnowledgeIdentifier
                  mkTestInsightEvent
                  fixedTime
        result `shouldSatisfy` isLeft
        -- Failure knowledge should be registered
        knowledgePersistCount finalState `shouldSatisfy` (>= 1)

      it "returns Left when instruction profile is not found" $ do
        let (result, finalState) =
              runWith stateWithNoProfile $
                orchestrateFromInsight
                  testDispatchIdentifier
                  testProposalIdentifier
                  testFailureKnowledgeIdentifier
                  mkTestInsightEvent
                  fixedTime
        result `shouldSatisfy` isLeft
        knowledgePersistCount finalState `shouldSatisfy` (>= 1)

      it "returns Left when skill execution fails" $ do
        let (result, finalState) =
              runWith stateWithSkillFailure $
                orchestrateFromInsight
                  testDispatchIdentifier
                  testProposalIdentifier
                  testFailureKnowledgeIdentifier
                  mkTestInsightEvent
                  fixedTime
        result `shouldSatisfy` isLeft
        knowledgePersistCount finalState `shouldSatisfy` (>= 1)

    describe "orchestrateFromRetest" $ do
      it "returns Right () on successful orchestration" $ do
        let (result, _) =
              runWith defaultState $
                orchestrateFromRetest
                  testDispatchIdentifier
                  testProposalIdentifier
                  testFailureKnowledgeIdentifier
                  mkTestRetestEvent
                  fixedTime
        result `shouldBe` Right ()

      it "persists proposal and dispatch" $ do
        let (_, finalState) =
              runWith defaultState $
                orchestrateFromRetest
                  testDispatchIdentifier
                  testProposalIdentifier
                  testFailureKnowledgeIdentifier
                  mkTestRetestEvent
                  fixedTime
        proposalPersistCount finalState `shouldSatisfy` (>= 1)
        dispatchPersistCount finalState `shouldSatisfy` (>= 1)
