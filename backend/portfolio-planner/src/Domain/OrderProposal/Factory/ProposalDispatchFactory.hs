{- | ProposalDispatchFactory — MUST-25.
純粋関数。signal.generated イベントのエンベロープから ProposalDispatch を生成する。
-}
module Domain.OrderProposal.Factory.ProposalDispatchFactory (
  fromSignalGeneratedEvent,
) where

import Domain.OrderProposal (Trace)
import Domain.OrderProposal.ProposalDispatch (
  ProposalDispatch,
  ProposalDispatchEvent,
  ProposalDispatchIdentifier,
  startDispatch,
 )
import Domain.OrderProposal.ValueObjects (SignalSnapshot)

{- | MUST-25: 入力イベントの identifier を ProposalDispatch.identifier に設定し、
初期 dispatchStatus を Pending にする。
純粋関数、外部 IO 非依存。
-}
fromSignalGeneratedEvent ::
  ProposalDispatchIdentifier ->
  SignalSnapshot ->
  Trace ->
  (ProposalDispatch, [ProposalDispatchEvent])
fromSignalGeneratedEvent inputIdentifier signalSnap traceValue =
  startDispatch inputIdentifier signalSnap traceValue
