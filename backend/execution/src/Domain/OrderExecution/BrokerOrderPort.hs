{- | Must-01 Must-14: BrokerOrderPort — ブローカー API 用 ACL Port。
ブローカー API への依存をインターフェース（型クラス）で抽象化する。
具体 HTTP/SDK 実装は infra/ACL 層に委ねる。戻り値はドメイン VO 'BrokerOutcome'。
-}
module Domain.OrderExecution.BrokerOrderPort (
  BrokerOutcome (..),
  BrokerOrderPort (..),
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.OrderExecution.Aggregate (BrokerOrder, ExecutionRequest)

{- | Must-14: ブローカー応答のドメイン表現。
HTTP ステータスや SDK エラーの解釈は ACL 層が行い、本 VO へ写像する。
-}
data BrokerOutcome
  = -- | 発注成功（ブローカー注文識別子・約定時刻）。
    BrokerAccepted
      { brokerOrder :: BrokerOrder
      , executedAt :: UTCTime
      }
  | {- | 発注失敗（ブローカー由来の生エラーラベル・再試行可否ヒント）。
    ReasonCode への正規化は 'Domain.OrderExecution.BrokerExecutionPolicy' が担う。
    -}
    BrokerRejected
      { errorLabel :: Text
      , detail :: Maybe Text
      , retryableHint :: Bool
      }
  deriving stock (Eq, Show)

{- | Must-14: BrokerOrderPort 型クラス Port。
外部 IO 型制約を持つが、型クラス定義自体はドメイン層に置く（ACL）。
-}
class (Monad m) => BrokerOrderPort m where
  placeOrder :: ExecutionRequest -> m BrokerOutcome
