{- | Repository port typeclasses — MUST-20, MUST-21, MUST-22, MUST-23.
No infrastructure types (Firestore, Pub/Sub etc.) are imported here.

Method names are prefixed per repository to avoid name clashes in a single module.
-}
module Domain.OrderProposal.Ports (
  -- * OrderProposalRepository (MUST-20)
  OrderProposalRepository (..),

  -- * ProposalDispatchRepository (MUST-21)
  ProposalDispatchRepository (..),

  -- * IdempotencyKeyRepository (MUST-22)
  IdempotencyKeyRepository (..),
) where

import Domain.OrderProposal.Aggregate (
  OrderProposal,
  OrderProposalIdentifier,
  OrderProposalSearchCriteria,
  OrderStatus,
 )
import Domain.OrderProposal.ProposalDispatch (
  ProposalDispatch,
  ProposalDispatchIdentifier,
 )

-- ---------------------------------------------------------------------
-- MUST-20: OrderProposalRepository
-- 5 メソッド: Find / FindByStatus / Search / Persist / Terminate
-- ---------------------------------------------------------------------

{- | OrderProposalRepository — Find / FindByStatus / Search / Persist / Terminate の 5 メソッド。
MUST-23: m は Monad 制約のみ — インフラ固有型を参照しない。
-}
class (Monad m) => OrderProposalRepository m where
  findOrderProposal :: OrderProposalIdentifier -> m (Maybe OrderProposal)
  findOrderProposalsByStatus :: OrderStatus -> m [OrderProposal]
  searchOrderProposals :: OrderProposalSearchCriteria -> m [OrderProposal]
  persistOrderProposal :: OrderProposal -> m ()
  terminateOrderProposal :: OrderProposalIdentifier -> m ()

-- ---------------------------------------------------------------------
-- MUST-21: ProposalDispatchRepository
-- 3 メソッド: Find / Persist / Terminate
-- ---------------------------------------------------------------------

{- | ProposalDispatchRepository — Find / Persist / Terminate の 3 メソッド。
MUST-23: m は Monad 制約のみ。
-}
class (Monad m) => ProposalDispatchRepository m where
  findProposalDispatch :: ProposalDispatchIdentifier -> m (Maybe ProposalDispatch)
  persistProposalDispatch :: ProposalDispatch -> m ()
  terminateProposalDispatch :: ProposalDispatchIdentifier -> m ()

-- ---------------------------------------------------------------------
-- MUST-22: IdempotencyKeyRepository
-- 3 メソッド: Find / Persist / Terminate
-- ---------------------------------------------------------------------

{- | IdempotencyKeyRepository — 冪等性キー管理 — Find / Persist / Terminate の 3 メソッド。
ProposalDispatch を冪等性キーレコードとして管理する。
MUST-23: m は Monad 制約のみ。
-}
class (Monad m) => IdempotencyKeyRepository m where
  findIdempotencyKey :: ProposalDispatchIdentifier -> m (Maybe ProposalDispatch)
  persistIdempotencyKey :: ProposalDispatch -> m ()
  terminateIdempotencyKey :: ProposalDispatchIdentifier -> m ()
