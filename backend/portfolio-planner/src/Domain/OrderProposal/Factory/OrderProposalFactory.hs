{- | OrderProposalFactory — MUST-24.
純粋関数。SignalSnapshot と StrategySnapshot から OrderProposal を生成する。
-}
module Domain.OrderProposal.Factory.OrderProposalFactory (
  fromSignalSnapshot,
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.OrderProposal (Trace)
import Domain.OrderProposal.Aggregate (
  OrderProposal,
  OrderProposalEvent,
  OrderProposalIdentifier,
  Side,
  createProposal,
 )
import Domain.OrderProposal.Error (DomainError)
import Domain.OrderProposal.ValueObjects (
  SignalSnapshot,
  StrategySnapshot,
 )

{- | MUST-24: SignalSnapshot + StrategySnapshot から OrderProposal を生成する。
成功時の status は必ず Proposed (INV-PP-001 経由)。
qty <= 0 のとき Left を返す (INV-PP-002 経由)。
純粋関数、外部 IO 非依存。
-}
fromSignalSnapshot ::
  OrderProposalIdentifier ->
  Text ->
  Side ->
  Rational ->
  SignalSnapshot ->
  StrategySnapshot ->
  Trace ->
  UTCTime ->
  Either DomainError (OrderProposal, [OrderProposalEvent])
fromSignalSnapshot inputIdentifier sym inputSide inputQty signalSnap =
  createProposal
    inputIdentifier
    sym
    inputSide
    inputQty
    signalSnap
    Nothing
