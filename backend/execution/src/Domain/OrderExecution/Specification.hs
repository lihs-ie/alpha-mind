{- | Must-17: execution の Specification 群（純粋・外部 IO 非依存, §4.5）。
ApprovedStatusSpecification: OrderExecution が APPROVED か判定（RULE-EX-001）。
RetryableFailureSpecification: FailureDetail が再試行可能か判定（RULE-EX-003）。
-}
module Domain.OrderExecution.Specification (
  ApprovedStatusSpecification (..),
  RetryableFailureSpecification (..),
  isApproved,
  isRetryableFailure,
) where

import Domain.OrderExecution.Aggregate (ExecutionStatus (..), FailureDetail (..), OrderExecution)

-- | RULE-EX-001: APPROVED 状態確認の Specification マーカー。
data ApprovedStatusSpecification = ApprovedStatusSpecification
  deriving stock (Eq, Show)

-- | RULE-EX-003: 再試行可否判定の Specification マーカー。
data RetryableFailureSpecification = RetryableFailureSpecification
  deriving stock (Eq, Show)

-- | Must-17: OrderExecution が APPROVED かを判定する純粋関数。
isApproved :: ApprovedStatusSpecification -> OrderExecution -> Bool
isApproved ApprovedStatusSpecification execution = execution.status == Approved

-- | Must-17: FailureDetail が再試行可能かを判定する純粋関数。
isRetryableFailure :: RetryableFailureSpecification -> FailureDetail -> Bool
isRetryableFailure RetryableFailureSpecification failure = failure.retryable
