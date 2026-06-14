module Main (main) where

import Domain.MarketCollection.AggregateSpec qualified
import Domain.MarketCollection.CollectionDispatchSpec qualified
import Domain.MarketCollection.CollectionQualityPolicySpec qualified
import Domain.MarketCollection.ReasonCodeSpec qualified
import Domain.MarketCollection.SourcePolicySpecificationServiceSpec qualified
import Domain.MarketCollectionSpec qualified
import Infrastructure.ACL.AlpacaMarketDataSourceTSpec qualified
import Infrastructure.ACL.JQuantsMarketDataSourceTSpec qualified
import Infrastructure.ACL.NisshokinCsvSourceAdapterSpec qualified
import Infrastructure.Idempotency.CollectionIdempotencySpec qualified
import Infrastructure.Logging.CloudLoggingCollectionAuditWriterSpec qualified
import Infrastructure.Normalization.MarketDataNormalizerSpec qualified
import Infrastructure.Publisher.PubSubCollectionEventPublisherSpec qualified
import Infrastructure.Repository.FirestoreCodecSpec qualified
import Infrastructure.Repository.FirestoreCollectionDispatchRepositorySpec qualified
import Infrastructure.Repository.FirestoreMarketCollectionRepositorySpec qualified
import Infrastructure.Repository.GcsMarketDataRepositorySpec qualified
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
    Infrastructure.ACL.JQuantsMarketDataSourceTSpec.spec
    Infrastructure.ACL.AlpacaMarketDataSourceTSpec.spec
    Infrastructure.ACL.NisshokinCsvSourceAdapterSpec.spec
    Infrastructure.Idempotency.CollectionIdempotencySpec.spec
    Infrastructure.Logging.CloudLoggingCollectionAuditWriterSpec.spec
    Infrastructure.Normalization.MarketDataNormalizerSpec.spec
    Infrastructure.Repository.GcsMarketDataRepositorySpec.spec
    Infrastructure.Repository.FirestoreCodecSpec.spec
    Infrastructure.Repository.FirestoreMarketCollectionRepositorySpec.spec
    Infrastructure.Repository.FirestoreCollectionDispatchRepositorySpec.spec
    Infrastructure.Publisher.PubSubCollectionEventPublisherSpec.spec
