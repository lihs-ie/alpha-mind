module Domain.InsightCollection.EvidenceCompletenessPolicySpec (spec) where

import Data.Either (isLeft, isRight)
import Data.Text (Text)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.InsightCollection.Aggregate (
  InsightRecord (..),
  InsightRecordIdentifier (..),
  SignalClass (..),
  SourceType (..),
 )
import Domain.InsightCollection.EvidenceCompletenessPolicy (
  validateEvidence,
 )
import Domain.InsightCollection.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

mkRecord :: Text -> Text -> InsightRecord
mkRecord url snippet =
  InsightRecord
    { identifier = InsightRecordIdentifier (mkULID 1)
    , sourceType = X
    , sourceUrl = url
    , evidenceSnippet = snippet
    , collectedAt = fixedTime
    , summary = "Test summary"
    , signalClass = EventNoise
    , soWhatScore = 0.5
    , skillVersion = "v1.0.0"
    }

validRecord :: InsightRecord
validRecord = mkRecord "https://x.com/status/1" "Market anomaly detected"

spec :: Spec
spec =
  describe "Domain.InsightCollection.EvidenceCompletenessPolicy" $ do
    -- Must-19, Must-22, TST-IC-003: RULE-IC-003 — 根拠情報完全性テスト
    describe "validateEvidence" $ do
      it "returns Right records when all have sourceUrl and evidenceSnippet" $ do
        validateEvidence [validRecord]
          `shouldSatisfy` isRight

      it "returns Left RequestValidationFailed when sourceUrl is empty (TST-IC-003)" $ do
        -- Must-22: sourceUrl 欠損 → RequestValidationFailed
        validateEvidence [mkRecord "" "valid snippet"]
          `shouldBe` Left RequestValidationFailed

      it "returns Left RequestValidationFailed when evidenceSnippet is empty (TST-IC-003)" $ do
        -- Must-22: evidenceSnippet 欠損 → RequestValidationFailed
        validateEvidence [mkRecord "https://x.com/status/1" ""]
          `shouldBe` Left RequestValidationFailed

      it "returns Left when mixed valid and invalid records" $ do
        validateEvidence [validRecord, mkRecord "" "snippet"]
          `shouldSatisfy` isLeft

      it "returns Right for empty record list" $ do
        validateEvidence []
          `shouldSatisfy` isRight

      it "is pure — no IO involved" $ do
        -- 型検査がそのまま証明。validateEvidence は Either ReasonCode [InsightRecord] を返す純粋関数。
        let result = validateEvidence [validRecord]
        result `shouldSatisfy` isRight

      it "validates multiple valid records successfully" $ do
        let records = [validRecord, mkRecord "https://github.com/repo/1" "Code pattern analysis"]
        validateEvidence records `shouldSatisfy` isRight
