module Domain.HypothesisOrchestration.Event (
  -- * Boundary-internal domain events (Must-17)
  OrchestrationDispatchStarted (..),
  HypothesisProposalComposed (..),
  HypothesisProposalBlocked (..),
  HypothesisProposalFailed (..),
) where

import Data.Text (Text)
import Domain.HypothesisOrchestration (Trace)
import Domain.HypothesisOrchestration.Aggregate (
  HypothesisProposalIdentifier,
  InstrumentType,
 )
import Domain.HypothesisOrchestration.OrchestrationDispatch (OrchestrationDispatchIdentifier)
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode)
import Domain.HypothesisOrchestration.ValueObjects (SourceEventType)

{- | Must-17: orchestration.dispatch.started
payload: identifier, sourceEventType, trace
-}
data OrchestrationDispatchStarted = OrchestrationDispatchStarted
  { identifier :: OrchestrationDispatchIdentifier
  , sourceEventType :: SourceEventType
  , trace :: Trace
  }
  deriving stock (Eq, Show)

{- | Must-17: hypothesis.proposal.composed
payload: identifier, symbol, instrumentType, skillVersion, instructionProfileVersion, trace
-}
data HypothesisProposalComposed = HypothesisProposalComposed
  { identifier :: HypothesisProposalIdentifier
  , symbol :: Text
  , instrumentType :: InstrumentType
  , skillVersion :: Text
  , instructionProfileVersion :: Text
  , trace :: Trace
  }
  deriving stock (Eq, Show)

{- | Must-17: hypothesis.proposal.blocked
payload: identifier, reasonCode, trace
-}
data HypothesisProposalBlocked = HypothesisProposalBlocked
  { identifier :: HypothesisProposalIdentifier
  , reasonCode :: ReasonCode
  , trace :: Trace
  }
  deriving stock (Eq, Show)

{- | Must-17: hypothesis.proposal.failed
payload: identifier, reasonCode, trace
-}
data HypothesisProposalFailed = HypothesisProposalFailed
  { identifier :: HypothesisProposalIdentifier
  , reasonCode :: ReasonCode
  , trace :: Trace
  }
  deriving stock (Eq, Show)
