{- | Must-17: ExternalSourcePort 型クラス Port — ACL 用。
実装は infra/ACL 層（Issue #53）に委ねる。
domain 層に HTTP クライアント等の IO 呼び出しを直接含まない。
-}
module Domain.InsightCollection.ExternalSourcePort (
  ExternalSourcePort (..),
) where

import Data.Time (Day)
import Domain.InsightCollection.Aggregate (
  FailureDetail,
  InsightRecord,
  SourcePolicySnapshot,
 )

{- | Must-17: ExternalSourcePort 型クラス Port。
外部 IO 型制約を持つが、型クラス定義自体はドメイン層に置く。
実装は ACL 層（Issue #53）が担う。
-}
class (Monad m) => ExternalSourcePort m where
  fetchInsights :: SourcePolicySnapshot -> Day -> m (Either FailureDetail [InsightRecord])
