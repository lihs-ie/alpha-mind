{- | Must-21: MarketDataSource 型クラス Port — ACL 用。
実装は infra/ACL 層（#26/#27）に委ねる。
Open question 解決: 設計書の指示に従い、戻り値は (Either FailureDetail [RawMarketRecord])
とし、ドメイン VO を返すシグネチャにする。RawMarketRecord のパース/変換は ACL 層の責務。
日商金固有メソッドは #27 ACL スコープ — 本層では汎用 Port として fetchJapanMarketData に集約。
-}
module Domain.MarketCollection.MarketDataSource (
  MarketDataSource (..),
) where

import Data.Time (Day)
import Domain.MarketCollection.Aggregate (FailureDetail)
import Domain.MarketCollection.CollectionQualityPolicy (RawMarketRecord)

{- | Must-21: MarketDataSource 型クラス Port。
外部IO型制約を持つが、型クラス定義自体はドメイン層に置く。
-}
class (Monad m) => MarketDataSource m where
  fetchJapanMarketData :: Day -> m (Either FailureDetail [RawMarketRecord])
  fetchUsMarketData :: Day -> m (Either FailureDetail [RawMarketRecord])
