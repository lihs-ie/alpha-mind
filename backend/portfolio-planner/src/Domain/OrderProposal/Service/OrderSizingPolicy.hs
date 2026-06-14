{- | OrderSizingPolicy — MUST-16.
純粋関数。注文数量を maxSingleOrderQty でキャップし、qty > 0 を保証する。
-}
module Domain.OrderProposal.Service.OrderSizingPolicy (
  calculateQuantity,
) where

import Domain.OrderProposal.Error (DomainError (..))
import Domain.OrderProposal.ValueObjects (StrategySnapshot (..))

{- | MUST-16: StrategySnapshot と希望数量を受け取り、実際の注文数量を返す。
qty を maxSingleOrderQty でキャップする。
結果 qty <= 0 となる入力はエラー。
外部 IO を含まない純粋関数。
-}
calculateQuantity ::
  StrategySnapshot ->
  Rational ->
  Either DomainError Rational
calculateQuantity strategy rawQty
  | rawQty <= 0 =
      Left (InvariantViolation "OrderSizingPolicy" "raw qty must be positive")
  | otherwise =
      let cappedQty = min rawQty strategy.maxSingleOrderQty
       in if cappedQty <= 0
            then Left (InvariantViolation "OrderSizingPolicy" "calculated qty must be positive")
            else Right cappedQty
