{- | Domain events re-exported from aggregate modules for convenience.
MUST-26, MUST-27, MUST-28, INV-PP-006.
-}
module Domain.OrderProposal.DomainEvent (
  -- * OrderProposal events (MUST-26)
  OrderProposalEvent (..),

  -- * ProposalDispatch events (MUST-27, MUST-28)
  ProposalDispatchEvent (..),
) where

import Domain.OrderProposal.Aggregate (OrderProposalEvent (..))
import Domain.OrderProposal.ProposalDispatch (ProposalDispatchEvent (..))
