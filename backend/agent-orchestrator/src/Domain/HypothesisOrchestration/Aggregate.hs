{-# LANGUAGE NoFieldSelectors #-}

module Domain.HypothesisOrchestration.Aggregate (
  -- * Identifiers
  HypothesisProposalIdentifier (..),

  -- * Status enum
  ProposalStatus (..),

  -- * Instrument Type
  InstrumentType (..),

  -- * Aggregate (construct via 'startProposal' only; constructor intentionally hidden)
  HypothesisProposal,

  -- * Smart constructor
  startProposal,

  -- * Commands
  attachGenerationContext,
  assessDuplicateRisk,
  completeProposal,
  blockProposal,
  failProposal,
  terminateProposal,

  -- * Domain Events
  HypothesisProposalEvent (..),

  -- * Repository Port
  ProposalSearchCriteria (..),
  emptyProposalSearchCriteria,
  HypothesisProposalRepository (..),
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.HypothesisOrchestration (Trace)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.ValueObjects (
  DuplicateAssessment,
  FailureKnowledgeSummary,
  GenerationContext,
  InsiderRiskLevel,
  ProposalArtifact,
  proposalArtifactReportPath,
 )
import GHC.Records (HasField (..))

-- ---------------------------------------------------------------------
-- Identifiers
-- ---------------------------------------------------------------------

-- | Must-36: 識別子型は HypothesisProposalIdentifier と命名。XXXId 形式は禁止。
newtype HypothesisProposalIdentifier = HypothesisProposalIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Status (Must-02)
-- ---------------------------------------------------------------------

-- | Must-02: 4状態のみ。
data ProposalStatus
  = Pending
  | Proposed
  | Blocked
  | Failed
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- InstrumentType
-- ---------------------------------------------------------------------

-- | 金融商品種別。
data InstrumentType
  = ETF
  | Stock
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Aggregate
--
-- コンストラクタは隠蔽。外部からは startProposal + コマンド関数で操作する。
-- フィールド名は hp プレフィックスで HasField 衝突を回避。
-- ---------------------------------------------------------------------

data HypothesisProposal = HypothesisProposal
  { hpIdentifier :: HypothesisProposalIdentifier
  , hpSymbol :: Maybe Text
  , hpInstrumentType :: Maybe InstrumentType
  , hpTitle :: Maybe Text
  , hpStatus :: ProposalStatus
  , hpSourceEvidence :: [Text]
  , hpSkillVersion :: Maybe Text
  , hpInstructionProfileVersion :: Maybe Text
  , hpInsiderRisk :: Maybe InsiderRiskLevel
  , hpMnpiSelfDeclared :: Maybe Bool
  , hpReasonCode :: Maybe ReasonCode
  , hpTrace :: Trace
  , hpDispatch :: Text
  -- ^ Must-10: dispatch は OrchestrationDispatch の識別子参照（文字列）のみ
  , hpReportPath :: Maybe Text
  , hpGenerationContext :: Maybe GenerationContext
  , hpDuplicateAssessment :: Maybe DuplicateAssessment
  , hpProposalArtifact :: Maybe ProposalArtifact
  , hpFailureKnowledgeSummary :: Maybe FailureKnowledgeSummary
  , hpCreatedAt :: UTCTime
  , hpUpdatedAt :: UTCTime
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Domain Events (Must-17)
-- ---------------------------------------------------------------------

-- | Must-17: HypothesisProposalEvent — 境界内ドメインイベント型。
data HypothesisProposalEvent
  = -- | orchestration.dispatch.started ペイロード相当の仮説提案開始
    HypothesisProposalStarted
      { identifier :: HypothesisProposalIdentifier
      , dispatch :: Text
      , trace :: Trace
      }
  | -- | hypothesis.proposal.composed ペイロード
    HypothesisProposalComposed
      { identifier :: HypothesisProposalIdentifier
      , symbol :: Text
      , instrumentType :: InstrumentType
      , skillVersion :: Text
      , instructionProfileVersion :: Text
      , trace :: Trace
      }
  | -- | hypothesis.proposal.blocked ペイロード
    HypothesisProposalBlocked
      { identifier :: HypothesisProposalIdentifier
      , reasonCode :: ReasonCode
      , trace :: Trace
      }
  | -- | hypothesis.proposal.failed ペイロード
    HypothesisProposalFailed
      { identifier :: HypothesisProposalIdentifier
      , reasonCode :: ReasonCode
      , trace :: Trace
      }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor — startProposal コマンド (Must-05: identifier は不変)
-- ---------------------------------------------------------------------

-- | Must-05: identifier はスマートコンストラクタで1度のみ設定される。
startProposal ::
  HypothesisProposalIdentifier ->
  Text ->
  Trace ->
  UTCTime ->
  (HypothesisProposal, [HypothesisProposalEvent])
startProposal proposalIdentifier dispatchReference traceValue now =
  let proposal =
        HypothesisProposal
          { hpIdentifier = proposalIdentifier
          , hpSymbol = Nothing
          , hpInstrumentType = Nothing
          , hpTitle = Nothing
          , hpStatus = Pending
          , hpSourceEvidence = []
          , hpSkillVersion = Nothing
          , hpInstructionProfileVersion = Nothing
          , hpInsiderRisk = Nothing
          , hpMnpiSelfDeclared = Nothing
          , hpReasonCode = Nothing
          , hpTrace = traceValue
          , hpDispatch = dispatchReference
          , hpReportPath = Nothing
          , hpGenerationContext = Nothing
          , hpDuplicateAssessment = Nothing
          , hpProposalArtifact = Nothing
          , hpFailureKnowledgeSummary = Nothing
          , hpCreatedAt = now
          , hpUpdatedAt = now
          }
      event =
        HypothesisProposalStarted
          { identifier = proposalIdentifier
          , dispatch = dispatchReference
          , trace = traceValue
          }
   in (proposal, [event])

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

-- | GenerationContext をアタッチする（Pending 状態のみ）。
attachGenerationContext ::
  GenerationContext ->
  UTCTime ->
  HypothesisProposal ->
  Either DomainError (HypothesisProposal, [HypothesisProposalEvent])
attachGenerationContext context now proposal
  | proposal.status /= Pending =
      Left (InvalidStateTransition (proposalStatusLabel proposal) "AttachGenerationContext" StateConflict)
  | otherwise =
      Right
        ( proposal
            { hpGenerationContext = Just context
            , hpUpdatedAt = now
            }
        , []
        )

-- | 重複リスク評価を記録する（Pending 状態のみ）。
assessDuplicateRisk ::
  DuplicateAssessment ->
  UTCTime ->
  HypothesisProposal ->
  Either DomainError (HypothesisProposal, [HypothesisProposalEvent])
assessDuplicateRisk assessment now proposal
  | proposal.status /= Pending =
      Left (InvalidStateTransition (proposalStatusLabel proposal) "AssessDuplicateRisk" StateConflict)
  | otherwise =
      Right
        ( proposal
            { hpDuplicateAssessment = Just assessment
            , hpUpdatedAt = now
            }
        , []
        )

{- | Must-03 INV-AO-001: Pending → Proposed 遷移。
status=proposed 時は symbol, instrumentType, title, sourceEvidence(非空),
skillVersion, instructionProfileVersion がすべて必須。
-}
completeProposal ::
  Text ->
  InstrumentType ->
  Text ->
  [Text] ->
  Text ->
  Text ->
  Maybe InsiderRiskLevel ->
  Maybe Bool ->
  ProposalArtifact ->
  UTCTime ->
  HypothesisProposal ->
  Either DomainError (HypothesisProposal, [HypothesisProposalEvent])
completeProposal
  sym
  instrType
  ttl
  evidence
  skillVer
  profileVer
  insiderRisk
  mnpiSelfDeclared
  artifact
  now
  proposal
    | proposal.status /= Pending =
        Left (InvalidStateTransition (proposalStatusLabel proposal) "CompleteProposal" StateConflict)
    | sym == "" =
        Left (MissingRequiredFields ["symbol"] RequestValidationFailed)
    | ttl == "" =
        Left (MissingRequiredFields ["title"] RequestValidationFailed)
    | null evidence =
        Left (InvariantViolation "HypothesisProposal" "sourceEvidence must be non-empty" RequestValidationFailed)
    | skillVer == "" =
        Left (MissingRequiredFields ["skillVersion"] RequestValidationFailed)
    | profileVer == "" =
        Left (MissingRequiredFields ["instructionProfileVersion"] RequestValidationFailed)
    | otherwise =
        let updated =
              proposal
                { hpStatus = Proposed
                , hpSymbol = Just sym
                , hpInstrumentType = Just instrType
                , hpTitle = Just ttl
                , hpSourceEvidence = evidence
                , hpSkillVersion = Just skillVer
                , hpInstructionProfileVersion = Just profileVer
                , hpInsiderRisk = insiderRisk
                , hpMnpiSelfDeclared = mnpiSelfDeclared
                , hpProposalArtifact = Just artifact
                , hpReportPath = Just (proposalArtifactReportPath artifact)
                , hpUpdatedAt = now
                }
            event =
              HypothesisProposalComposed
                { identifier = proposal.identifier
                , symbol = sym
                , instrumentType = instrType
                , skillVersion = skillVer
                , instructionProfileVersion = profileVer
                , trace = proposal.trace
                }
         in Right (updated, [event])

{- | Must-04 INV-AO-002: Pending → Blocked 遷移。
reasonCode は必須（コマンド引数で必ず渡す）。
Must-42 RULE-AO-003: blockProposal の reasonCode は STATE_CONFLICT を設定。
-}
blockProposal ::
  ReasonCode ->
  FailureKnowledgeSummary ->
  UTCTime ->
  HypothesisProposal ->
  Either DomainError (HypothesisProposal, [HypothesisProposalEvent])
blockProposal code knowledgeSummary now proposal
  | proposal.status /= Pending =
      Left (InvalidStateTransition (proposalStatusLabel proposal) "BlockProposal" StateConflict)
  | otherwise =
      let updated =
            proposal
              { hpStatus = Blocked
              , hpReasonCode = Just code
              , hpFailureKnowledgeSummary = Just knowledgeSummary
              , hpUpdatedAt = now
              }
          event =
            HypothesisProposalBlocked
              { identifier = proposal.identifier
              , reasonCode = code
              , trace = proposal.trace
              }
       in Right (updated, [event])

-- | Must-04 INV-AO-002: Pending → Failed 遷移。reasonCode は必須。
failProposal ::
  ReasonCode ->
  UTCTime ->
  HypothesisProposal ->
  Either DomainError (HypothesisProposal, [HypothesisProposalEvent])
failProposal code now proposal
  | proposal.status /= Pending =
      Left (InvalidStateTransition (proposalStatusLabel proposal) "FailProposal" StateConflict)
  | otherwise =
      let updated =
            proposal
              { hpStatus = Failed
              , hpReasonCode = Just code
              , hpUpdatedAt = now
              }
          event =
            HypothesisProposalFailed
              { identifier = proposal.identifier
              , reasonCode = code
              , trace = proposal.trace
              }
       in Right (updated, [event])

-- | TerminateProposal — 管理コマンド（純粋、イベントなし）。
terminateProposal :: HypothesisProposal -> HypothesisProposal
terminateProposal = id

-- ---------------------------------------------------------------------
-- Repository Port (Must-18)
-- ---------------------------------------------------------------------

data ProposalSearchCriteria = ProposalSearchCriteria
  { statusFilter :: Maybe ProposalStatus
  , symbolFilter :: Maybe Text
  , limitCount :: Maybe Int
  }
  deriving stock (Eq, Show)

emptyProposalSearchCriteria :: ProposalSearchCriteria
emptyProposalSearchCriteria =
  ProposalSearchCriteria
    { statusFilter = Nothing
    , symbolFilter = Nothing
    , limitCount = Nothing
    }

-- | Must-18: HypothesisProposalRepository 型クラス Port（実装は infra 層）。
class (Monad m) => HypothesisProposalRepository m where
  find :: HypothesisProposalIdentifier -> m (Maybe HypothesisProposal)
  findByStatus :: ProposalStatus -> m [HypothesisProposal]
  search :: ProposalSearchCriteria -> m [HypothesisProposal]
  persist :: HypothesisProposal -> m ()
  terminate :: HypothesisProposalIdentifier -> m ()

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

proposalStatusLabel :: HypothesisProposal -> Text
proposalStatusLabel proposal = case proposal.status of
  Pending -> "pending"
  Proposed -> "proposed"
  Blocked -> "blocked"
  Failed -> "failed"

-- ---------------------------------------------------------------------
-- Read-only field access via HasField
-- ---------------------------------------------------------------------

instance HasField "identifier" HypothesisProposal HypothesisProposalIdentifier where
  getField HypothesisProposal{hpIdentifier = x} = x

instance HasField "symbol" HypothesisProposal (Maybe Text) where
  getField HypothesisProposal{hpSymbol = x} = x

instance HasField "instrumentType" HypothesisProposal (Maybe InstrumentType) where
  getField HypothesisProposal{hpInstrumentType = x} = x

instance HasField "title" HypothesisProposal (Maybe Text) where
  getField HypothesisProposal{hpTitle = x} = x

instance HasField "status" HypothesisProposal ProposalStatus where
  getField HypothesisProposal{hpStatus = x} = x

instance HasField "sourceEvidence" HypothesisProposal [Text] where
  getField HypothesisProposal{hpSourceEvidence = x} = x

instance HasField "skillVersion" HypothesisProposal (Maybe Text) where
  getField HypothesisProposal{hpSkillVersion = x} = x

instance HasField "instructionProfileVersion" HypothesisProposal (Maybe Text) where
  getField HypothesisProposal{hpInstructionProfileVersion = x} = x

instance HasField "insiderRisk" HypothesisProposal (Maybe InsiderRiskLevel) where
  getField HypothesisProposal{hpInsiderRisk = x} = x

instance HasField "mnpiSelfDeclared" HypothesisProposal (Maybe Bool) where
  getField HypothesisProposal{hpMnpiSelfDeclared = x} = x

instance HasField "reasonCode" HypothesisProposal (Maybe ReasonCode) where
  getField HypothesisProposal{hpReasonCode = x} = x

instance HasField "trace" HypothesisProposal Trace where
  getField HypothesisProposal{hpTrace = x} = x

instance HasField "dispatch" HypothesisProposal Text where
  getField HypothesisProposal{hpDispatch = x} = x

instance HasField "reportPath" HypothesisProposal (Maybe Text) where
  getField HypothesisProposal{hpReportPath = x} = x

instance HasField "generationContext" HypothesisProposal (Maybe GenerationContext) where
  getField HypothesisProposal{hpGenerationContext = x} = x

instance HasField "duplicateAssessment" HypothesisProposal (Maybe DuplicateAssessment) where
  getField HypothesisProposal{hpDuplicateAssessment = x} = x

instance HasField "proposalArtifact" HypothesisProposal (Maybe ProposalArtifact) where
  getField HypothesisProposal{hpProposalArtifact = x} = x

instance HasField "failureKnowledgeSummary" HypothesisProposal (Maybe FailureKnowledgeSummary) where
  getField HypothesisProposal{hpFailureKnowledgeSummary = x} = x

instance HasField "createdAt" HypothesisProposal UTCTime where
  getField HypothesisProposal{hpCreatedAt = x} = x

instance HasField "updatedAt" HypothesisProposal UTCTime where
  getField HypothesisProposal{hpUpdatedAt = x} = x
