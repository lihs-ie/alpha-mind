module Main (main) where

import Domain.MarketCollection.AggregateSpec qualified
import Domain.MarketCollection.CollectionDispatchSpec qualified
import Domain.MarketCollection.CollectionQualityPolicySpec qualified
import Domain.MarketCollection.ReasonCodeSpec qualified
import Domain.MarketCollection.SourcePolicySpecificationServiceSpec qualified
import Domain.MarketCollectionSpec qualified
import Test.Hspec (hspec)
import UseCase.CollectMarketDataSpec qualified

main :: IO ()
main =
  hspec $ do
    Domain.MarketCollectionSpec.spec
    Domain.MarketCollection.ReasonCodeSpec.spec
    Domain.MarketCollection.AggregateSpec.spec
    Domain.MarketCollection.CollectionDispatchSpec.spec
    Domain.MarketCollection.SourcePolicySpecificationServiceSpec.spec
    Domain.MarketCollection.CollectionQualityPolicySpec.spec
    UseCase.CollectMarketDataSpec.spec
