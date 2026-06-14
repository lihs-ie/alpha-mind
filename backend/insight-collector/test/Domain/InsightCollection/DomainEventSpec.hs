module Domain.InsightCollection.DomainEventSpec (spec) where

import Data.ULID (ULID, ulidFromInteger)
import Domain.InsightCollection (Trace (..))
import Domain.InsightCollection.Aggregate (
  InsightCollectionIdentifier (..),
  SourceCollectionStatus (..),
  SourceOutcome (..),
  SourceType (..),
 )
import Domain.InsightCollection.DomainEvent (InsightCollectionEvent (..))
import Domain.InsightCollection.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

testIdentifier :: InsightCollectionIdentifier
testIdentifier = InsightCollectionIdentifier (mkULID 1)

testTrace :: Trace
testTrace = Trace (mkULID 100)

testSourceCollectionStatus :: SourceCollectionStatus
testSourceCollectionStatus =
  SourceCollectionStatus
    { sourceType = X
    , status = SourceSuccess
    }

spec :: Spec
spec =
  describe "Domain.InsightCollection.DomainEvent" $ do
    -- Must-10: 3バリアントのドメインイベント型テスト
    describe "InsightCollectionEvent" $ do
      it "CollectionStarted holds identifier and trace" $ do
        let event =
              CollectionStarted
                { identifier = testIdentifier
                , trace = testTrace
                }
        event.identifier `shouldBe` testIdentifier
        event.trace `shouldBe` testTrace

      it "CollectionCompleted holds identifier, count, storagePath, sourceStatus, partialFailure, and trace" $ do
        let event =
              CollectionCompleted
                { identifier = testIdentifier
                , count = 10
                , storagePath = "/insight/2026-01-15.parquet"
                , sourceStatus = [testSourceCollectionStatus]
                , partialFailure = False
                , trace = testTrace
                }
        event.identifier `shouldBe` testIdentifier
        event.count `shouldBe` 10
        event.storagePath `shouldBe` "/insight/2026-01-15.parquet"
        event.partialFailure `shouldBe` False
        event.trace `shouldBe` testTrace
        length event.sourceStatus `shouldBe` 1

      it "CollectionFailed holds identifier, reasonCode, sourceType, stage, detail, and trace" $ do
        let event =
              CollectionFailed
                { identifier = testIdentifier
                , reasonCode = DependencyTimeout
                , sourceType = Just X
                , stage = Nothing
                , detail = Just "X API timeout"
                , trace = testTrace
                }
        event.identifier `shouldBe` testIdentifier
        event.reasonCode `shouldBe` DependencyTimeout
        event.sourceType `shouldBe` Just X
        event.detail `shouldBe` Just "X API timeout"
        event.trace `shouldBe` testTrace

      it "distinguishes all 3 event types" $ do
        let started = CollectionStarted testIdentifier testTrace
        let completed =
              CollectionCompleted
                { identifier = testIdentifier
                , count = 0
                , storagePath = "/p"
                , sourceStatus = []
                , partialFailure = False
                , trace = testTrace
                }
        let failed =
              CollectionFailed
                { identifier = testIdentifier
                , reasonCode = DependencyTimeout
                , sourceType = Nothing
                , stage = Nothing
                , detail = Nothing
                , trace = testTrace
                }
        started `shouldNotBe` completed
        completed `shouldNotBe` failed
