{- | ProposalBatchConsistencySpecification — MUST-19.
純粋関数。dispatchStatus == Completed かつ length orders /= orderCount のとき False を返す。
-}
module Domain.OrderProposal.Specification.ProposalBatchConsistencySpecification (
  isSatisfiedBy,
) where

import Domain.OrderProposal.ProposalDispatch (DispatchStatus (..), ProposalDispatch)

{- | MUST-19: dispatchStatus == Completed のとき orderCount == length orders を確認する。
Pending / Failed 状態では orderCount が Nothing の場合があるため True を返す。
純粋関数、外部 IO 非依存。
-}
isSatisfiedBy :: ProposalDispatch -> Bool
isSatisfiedBy dispatch =
  case dispatch.dispatchStatus of
    Completed ->
      case dispatch.orderCount of
        Nothing -> False
        Just count -> count == length dispatch.orders
    _ -> True
