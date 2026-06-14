{- | Must-10: insight-collector ドメインイベント型。
境界内ドメインイベント: insight.collection.started / insight.collection.completed / insight.collection.failed。
-}
module Domain.InsightCollection.DomainEvent (
  InsightCollectionEvent (..),
) where

import Data.Text (Text)
import Domain.InsightCollection (Trace)
import Domain.InsightCollection.Aggregate (
  FailureStage,
  InsightCollectionIdentifier,
  SourceCollectionStatus,
  SourceType,
 )
import Domain.InsightCollection.ReasonCode (ReasonCode)

{- | Must-10: 3種類のドメインイベント型。

- CollectionStarted: identifier/trace を含む (insight.collection.started)
- CollectionCompleted: identifier/trace/count/storagePath/sourceStatus/partialFailure を含む
  (insight.collection.completed)
- CollectionFailed: identifier/trace/reasonCode/sourceType/stage/detail を含む
  (insight.collection.failed)
-}
data InsightCollectionEvent
  = CollectionStarted
      { identifier :: InsightCollectionIdentifier
      , trace :: Trace
      }
  | CollectionCompleted
      { identifier :: InsightCollectionIdentifier
      , count :: Int
      , storagePath :: Text
      , sourceStatus :: [SourceCollectionStatus]
      , partialFailure :: Bool
      , trace :: Trace
      }
  | CollectionFailed
      { identifier :: InsightCollectionIdentifier
      , reasonCode :: ReasonCode
      , sourceType :: Maybe SourceType
      , stage :: Maybe FailureStage
      , detail :: Maybe Text
      , trace :: Trace
      }
  deriving stock (Eq, Show)
