module Domain.HypothesisOrchestration.HypothesisProposalFactory (
  -- * Factory input types
  InsightCollectedEvent (..),
  RetestRequestedEvent (..),

  -- * Factory (Must-31)
  fromInsightCollected,
  fromRetestRequested,
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.HypothesisOrchestration (Trace)
import Domain.HypothesisOrchestration.Aggregate (
  HypothesisProposal,
  HypothesisProposalEvent,
  HypothesisProposalIdentifier,
  startProposal,
 )

-- ---------------------------------------------------------------------
-- Factory Input Types
-- ---------------------------------------------------------------------

-- | insight.collected イベントペイロード（ACL 変換後の値）。
data InsightCollectedEvent = InsightCollectedEvent
  { insightIdentifier :: Text
  , dispatchReference :: Text
  , trace :: Trace
  , occurredAt :: UTCTime
  }
  deriving stock (Eq, Show)

-- | hypothesis.retest.requested イベントペイロード（ACL 変換後の値）。
data RetestRequestedEvent = RetestRequestedEvent
  { retestIdentifier :: Text
  , dispatchReference :: Text
  , trace :: Trace
  , occurredAt :: UTCTime
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Factory (Must-31)
-- ---------------------------------------------------------------------

-- | Must-31: insight.collected イベントから HypothesisProposal を生成するファクトリ。
fromInsightCollected ::
  HypothesisProposalIdentifier ->
  InsightCollectedEvent ->
  (HypothesisProposal, [HypothesisProposalEvent])
fromInsightCollected proposalIdentifier event =
  startProposal proposalIdentifier event.dispatchReference event.trace event.occurredAt

-- | Must-31: hypothesis.retest.requested イベントから HypothesisProposal を生成するファクトリ。
fromRetestRequested ::
  HypothesisProposalIdentifier ->
  RetestRequestedEvent ->
  (HypothesisProposal, [HypothesisProposalEvent])
fromRetestRequested proposalIdentifier event =
  startProposal proposalIdentifier event.dispatchReference event.trace event.occurredAt
