{-# LANGUAGE NoFieldSelectors #-}

{- | Must-18 Must-19 Must-20 Must-21: DemoRunEvaluation 集約。
デモ完了通知の発行状態を確定する。完了通知の重複発行を禁止する（INV-EX-004, RULE-EX-007）。
-}
module Domain.OrderExecution.DemoRunEvaluation (
  -- * Identifiers
  DemoRunEvaluationIdentifier (..),
  DemoRun (..),

  -- * Status enum
  DemoRunStatus (..),

  -- * Value Objects
  InstrumentType (..),
  InsiderRisk (..),
  DemoPerformance (..),
  PromotionGate (..),

  -- * Aggregate (construct via 'startDemoRun' only; constructor hidden)
  DemoRunEvaluation,

  -- * Smart constructor
  startDemoRun,

  -- * Commands
  completeDemoRun,
  markPublished,
  terminateDemoRunEvaluation,

  -- * Domain Events
  DemoRunEvaluationEvent (..),

  -- * Specification
  DemoRunCompletedSpecification (..),
  isDemoRunCompleted,

  -- * Repository Port
  DemoRunEvaluationRepository (..),
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.OrderExecution (Trace)
import Domain.OrderExecution.Error (DomainError (..))
import GHC.Records (HasField (..))

-- ---------------------------------------------------------------------
-- Identifiers
-- ---------------------------------------------------------------------

-- | Must-02: 仮説識別子（DemoRunEvaluation の自集約識別子）。
newtype DemoRunEvaluationIdentifier = DemoRunEvaluationIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- | Must-02: デモ実行識別子（他関心ごとの識別子）。
newtype DemoRun = DemoRun {value :: Text}
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------

-- | Must-18: デモ評価状態。2値（§4.1.3）。
data DemoRunStatus
  = Active
  | Completed
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Value Objects (Must-19)
-- ---------------------------------------------------------------------

-- | Must-19: 金融商品種別（asyncapi instrumentType）。
data InstrumentType
  = ETF
  | Stock
  deriving stock (Eq, Ord, Show)

-- | Must-19: インサイダーリスク区分（asyncapi insiderRisk）。
data InsiderRisk
  = Low
  | Medium
  | High
  deriving stock (Eq, Ord, Show)

-- | Must-19: DemoPerformance — デモ評価指標。
data DemoPerformance = DemoPerformance
  { costAdjustedReturn :: Maybe Double
  , dsr :: Maybe Double
  , pbo :: Maybe Double
  , demoPeriodDays :: Int
  }
  deriving stock (Eq, Show)

-- | Must-19: PromotionGate — 昇格可否入力情報。
data PromotionGate = PromotionGate
  { instrumentType :: InstrumentType
  , insiderRisk :: InsiderRisk
  , mnpiSelfDeclared :: Bool
  , requiresComplianceReview :: Bool
  , promotable :: Bool
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Domain Events (Must-18)
-- ---------------------------------------------------------------------

{- | Must-18: DemoRunEvaluationEvent。
完了確定後に DemoRunCompleted を発行する。identifier と trace を含む。
-}
data DemoRunEvaluationEvent = DemoRunCompleted
  { identifier :: DemoRunEvaluationIdentifier
  , demoRun :: DemoRun
  , trace :: Trace
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Aggregate
--
-- コンストラクタは隠蔽。フィールド名は dr プレフィックスで HasField 衝突を回避。
-- ---------------------------------------------------------------------

data DemoRunEvaluation = DemoRunEvaluation
  { drIdentifier :: DemoRunEvaluationIdentifier
  , drDemoRun :: DemoRun
  , drStatus :: DemoRunStatus
  , drStartedAt :: UTCTime
  , drEndedAt :: Maybe UTCTime
  , drPublished :: Bool
  , drTrace :: Trace
  , drPerformance :: Maybe DemoPerformance
  , drPromotionGate :: Maybe PromotionGate
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor — StartDemoRun コマンド (Must-18)
-- ---------------------------------------------------------------------

-- | Must-18: デモ実行を開始する。status=Active, published=False で初期化。identifier は不変。
startDemoRun ::
  DemoRunEvaluationIdentifier ->
  DemoRun ->
  UTCTime ->
  Trace ->
  DemoRunEvaluation
startDemoRun evaluationIdentifier demoRunValue startedAtValue traceValue =
  DemoRunEvaluation
    { drIdentifier = evaluationIdentifier
    , drDemoRun = demoRunValue
    , drStatus = Active
    , drStartedAt = startedAtValue
    , drEndedAt = Nothing
    , drPublished = False
    , drTrace = traceValue
    , drPerformance = Nothing
    , drPromotionGate = Nothing
    }

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

{- | Must-18 INV-EX-004 RULE-EX-007: デモ完了を確定する。
status=Active のときのみ Completed へ1回だけ遷移し DemoRunCompleted を発行する。
既に Completed からの再完了は Left（冪等扱い, Must-10）。副作用なし。
-}
completeDemoRun ::
  DemoPerformance ->
  PromotionGate ->
  UTCTime ->
  DemoRunEvaluation ->
  Either DomainError (DemoRunEvaluation, [DemoRunEvaluationEvent])
completeDemoRun performance promotionGate endedAtValue evaluation
  | evaluation.status /= Active =
      Left (InvalidStateTransition (statusLabel evaluation) "CompleteDemoRun")
  | otherwise =
      let updated =
            evaluation
              { drStatus = Completed
              , drEndedAt = Just endedAtValue
              , drPerformance = Just performance
              , drPromotionGate = Just promotionGate
              }
          event =
            DemoRunCompleted
              { identifier = evaluation.identifier
              , demoRun = evaluation.demoRun
              , trace = evaluation.trace
              }
       in Right (updated, [event])

{- | Must-18: 完了通知を発行済みとして記録する。
published=True へ更新。重複発行防止（INV-EX-004）。既に published のときは冪等に no-op（イベントなし）。
-}
markPublished :: DemoRunEvaluation -> DemoRunEvaluation
markPublished evaluation = evaluation{drPublished = True}

-- | TerminateDemoRunEvaluation — 管理コマンド（純粋、イベントなし）。
terminateDemoRunEvaluation :: DemoRunEvaluation -> DemoRunEvaluation
terminateDemoRunEvaluation = id

-- ---------------------------------------------------------------------
-- Specification (Must-21)
-- ---------------------------------------------------------------------

-- | RULE-EX-007: デモ完了条件判定の Specification マーカー。
data DemoRunCompletedSpecification = DemoRunCompletedSpecification
  deriving stock (Eq, Show)

{- | Must-21: デモが完了状態かを判定する純粋関数。
未発行（published=False）かつ Completed のとき True（完了通知が発行可能な状態）。
-}
isDemoRunCompleted :: DemoRunCompletedSpecification -> DemoRunEvaluation -> Bool
isDemoRunCompleted DemoRunCompletedSpecification evaluation =
  evaluation.status == Completed && not evaluation.published

-- ---------------------------------------------------------------------
-- Repository Port (Must-20)
-- ---------------------------------------------------------------------

{- | Must-20: DemoRunEvaluationRepository 型クラス Port（実装は infra 層）。
§4.5.1 命名規則: Find / Persist / Terminate。
-}
class (Monad m) => DemoRunEvaluationRepository m where
  find :: DemoRunEvaluationIdentifier -> m (Maybe DemoRunEvaluation)
  persist :: DemoRunEvaluation -> m ()
  terminate :: DemoRunEvaluationIdentifier -> m ()

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

statusLabel :: DemoRunEvaluation -> Text
statusLabel evaluation = case evaluation.status of
  Active -> "active"
  Completed -> "completed"

-- ---------------------------------------------------------------------
-- Read-only field access via HasField
-- ---------------------------------------------------------------------

instance HasField "identifier" DemoRunEvaluation DemoRunEvaluationIdentifier where
  getField DemoRunEvaluation{drIdentifier = x} = x

instance HasField "demoRun" DemoRunEvaluation DemoRun where
  getField DemoRunEvaluation{drDemoRun = x} = x

instance HasField "status" DemoRunEvaluation DemoRunStatus where
  getField DemoRunEvaluation{drStatus = x} = x

instance HasField "startedAt" DemoRunEvaluation UTCTime where
  getField DemoRunEvaluation{drStartedAt = x} = x

instance HasField "endedAt" DemoRunEvaluation (Maybe UTCTime) where
  getField DemoRunEvaluation{drEndedAt = x} = x

instance HasField "published" DemoRunEvaluation Bool where
  getField DemoRunEvaluation{drPublished = x} = x

instance HasField "trace" DemoRunEvaluation Trace where
  getField DemoRunEvaluation{drTrace = x} = x

instance HasField "performance" DemoRunEvaluation (Maybe DemoPerformance) where
  getField DemoRunEvaluation{drPerformance = x} = x

instance HasField "promotionGate" DemoRunEvaluation (Maybe PromotionGate) where
  getField DemoRunEvaluation{drPromotionGate = x} = x
