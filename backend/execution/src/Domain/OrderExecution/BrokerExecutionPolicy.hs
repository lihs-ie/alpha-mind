{- | Must-15: BrokerExecutionPolicy — ドメインサービス（純粋）。
ブローカー応答 'BrokerOutcome' を 'ReasonCode' と再試行可否へ正規化する。
Firestore アクセスや外部 API 呼び出しを含まない（§4.4）。
-}
module Domain.OrderExecution.BrokerExecutionPolicy (
  ClassifiedOutcome (..),
  classifyOutcome,
) where

import Data.Char (toUpper)
import Data.Text (Text)
import Data.Text qualified as Text
import Domain.OrderExecution.Aggregate (BrokerOrder, FailureDetail (..))
import Domain.OrderExecution.BrokerOrderPort (BrokerOutcome (..))
import Domain.OrderExecution.ReasonCode (ReasonCode (..))

-- | classifyOutcome の結果。成功なら brokerOrder、失敗なら正規化済み FailureDetail。
data ClassifiedOutcome
  = ClassifiedSuccess BrokerOrder
  | ClassifiedFailure FailureDetail
  deriving stock (Eq, Show)

{- | Must-15: ブローカー応答を ReasonCode + retryable へ正規化する純粋関数。
非 retryable な業務エラー（market closed / insufficient funds / rejected）は即時失敗、
timeout / dependency 系は retryable とする（error-codes.json の retryable 区分に整合）。
未知エラーは retryableHint を尊重しつつ DEPENDENCY_UNAVAILABLE / EXECUTION_BROKER_REJECTED に倒す。
-}
classifyOutcome :: BrokerOutcome -> ClassifiedOutcome
classifyOutcome (BrokerAccepted brokerOrderValue _) = ClassifiedSuccess brokerOrderValue
classifyOutcome (BrokerRejected errorLabelValue detailValue retryableHintValue) =
  let reasonCode = classifyReasonCode errorLabelValue retryableHintValue
   in ClassifiedFailure
        FailureDetail
          { reasonCode = reasonCode
          , detail = detailValue
          , retryable = isRetryable reasonCode
          }

-- | 正規化されたエラーラベルから ReasonCode を決定する。
classifyReasonCode :: Text -> Bool -> ReasonCode
classifyReasonCode errorLabelValue retryableHintValue =
  case normalize errorLabelValue of
    "EXECUTION_BROKER_TIMEOUT" -> ExecutionBrokerTimeout
    "TIMEOUT" -> ExecutionBrokerTimeout
    "EXECUTION_MARKET_CLOSED" -> ExecutionMarketClosed
    "MARKET_CLOSED" -> ExecutionMarketClosed
    "EXECUTION_INSUFFICIENT_FUNDS" -> ExecutionInsufficientFunds
    "INSUFFICIENT_FUNDS" -> ExecutionInsufficientFunds
    "EXECUTION_BROKER_REJECTED" -> ExecutionBrokerRejected
    "REJECTED" -> ExecutionBrokerRejected
    "DEPENDENCY_UNAVAILABLE" -> DependencyUnavailable
    "DEPENDENCY_TIMEOUT" -> DependencyTimeout
    _
      | retryableHintValue -> DependencyUnavailable
      | otherwise -> ExecutionBrokerRejected

-- | error-codes.json の retryable 区分に整合する再試行可否。
isRetryable :: ReasonCode -> Bool
isRetryable code = case code of
  ExecutionBrokerTimeout -> True
  DependencyUnavailable -> True
  DependencyTimeout -> True
  ExecutionBrokerRejected -> False
  ExecutionMarketClosed -> False
  ExecutionInsufficientFunds -> False
  IdempotencyDuplicateEvent -> False
  StateConflict -> False

normalize :: Text -> Text
normalize = Text.map toUpper . Text.strip
