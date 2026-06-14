module Domain.RiskAssessment.Service.RiskScreeningPolicySpec (spec) where

import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.RiskAssessment.ReasonCode (OperatorActionReasonCode (..), ReasonCode (..))
import Domain.RiskAssessment.Service.RiskScreeningPolicy (
  ComplianceSpecification (..),
  RiskLimitSpecification (..),
  isSatisfiedByCompliance,
  isSatisfiedByRiskLimits,
  screenOrder,
 )
import Domain.RiskAssessment.ValueObjects (
  BlackoutWindow (..),
  CompliancePolicy (..),
  Decision (..),
  OrderProposal (..),
  OrderRiskAssessmentIdentifier (..),
  RiskExposure (..),
  RiskLimits (..),
  Side (..),
 )
import Test.Hspec (Spec, describe, it, shouldBe)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

beforeWindow :: UTCTime
beforeWindow = UTCTime (fromGregorian 2026 1 10) 0

afterWindow :: UTCTime
afterWindow = UTCTime (fromGregorian 2026 1 20) 0

windowStart :: UTCTime
windowStart = UTCTime (fromGregorian 2026 1 13) 0

windowEnd :: UTCTime
windowEnd = UTCTime (fromGregorian 2026 1 17) 0

testProposal :: OrderProposal
testProposal =
  OrderProposal
    { identifier = OrderRiskAssessmentIdentifier (mkULID 1)
    , symbol = "7203.T"
    , side = Buy
    , qty = 100.0
    }

defaultLimits :: RiskLimits
defaultLimits =
  RiskLimits
    { dailyLossLimit = 0.05
    , positionConcentrationLimit = 0.20
    , dailyOrderLimit = 50
    }

defaultExposure :: RiskExposure
defaultExposure =
  RiskExposure
    { dailyLossRate = 0.01
    , positionConcentrationRate = 0.05
    , dailyOrderCount = 5
    }

emptyPolicy :: CompliancePolicy
emptyPolicy =
  CompliancePolicy
    { restrictedSymbols = []
    , partnerRestrictedSymbols = []
    , blackoutWindows = []
    }

spec :: Spec
spec =
  describe "Domain.RiskAssessment.Service.RiskScreeningPolicy" $ do
    -- TST-RG-002: killSwitchEnabled=true always returns KILL_SWITCH_ENABLED
    describe "TST-RG-002: kill switch enabled" $ do
      it "rejects with KillSwitchEnabled when kill switch is on" $ do
        let result = screenOrder True True defaultLimits defaultExposure emptyPolicy testProposal fixedTime
        result `shouldBe` Left KillSwitchEnabled

      it "does not reject on kill switch when it is off" $ do
        let result = screenOrder True False defaultLimits defaultExposure emptyPolicy testProposal fixedTime
        result `shouldBe` Right Approved'

    -- TST-RG-003: dailyLossRate >= dailyLossLimit → RISK_LIMIT_EXCEEDED
    describe "TST-RG-003: risk limit exceeded" $ do
      it "rejects when dailyLossRate equals dailyLossLimit" $ do
        let exposure = defaultExposure{dailyLossRate = 0.05}
        let result = screenOrder True False defaultLimits exposure emptyPolicy testProposal fixedTime
        result `shouldBe` Left RiskLimitExceeded

      it "rejects when dailyLossRate exceeds dailyLossLimit" $ do
        let exposure = defaultExposure{dailyLossRate = 0.10}
        let result = screenOrder True False defaultLimits exposure emptyPolicy testProposal fixedTime
        result `shouldBe` Left RiskLimitExceeded

      it "rejects when positionConcentrationRate equals positionConcentrationLimit" $ do
        let exposure = defaultExposure{positionConcentrationRate = 0.20}
        let result = screenOrder True False defaultLimits exposure emptyPolicy testProposal fixedTime
        result `shouldBe` Left RiskLimitExceeded

      it "rejects when dailyOrderCount equals dailyOrderLimit" $ do
        let exposure = defaultExposure{dailyOrderCount = 50}
        let result = screenOrder True False defaultLimits exposure emptyPolicy testProposal fixedTime
        result `shouldBe` Left RiskLimitExceeded

      it "approves when all limits are below threshold" $ do
        let result = screenOrder True False defaultLimits defaultExposure emptyPolicy testProposal fixedTime
        result `shouldBe` Right Approved'

    -- TST-RG-004: symbol in restrictedSymbols → COMPLIANCE_RESTRICTED_SYMBOL
    describe "TST-RG-004: restricted symbol" $ do
      it "rejects when symbol is in restrictedSymbols" $ do
        let policy = emptyPolicy{restrictedSymbols = ["7203.T", "6758.T"]}
        let result = screenOrder True False defaultLimits defaultExposure policy testProposal fixedTime
        result `shouldBe` Left ComplianceRestrictedSymbol

      it "rejects when symbol is in partnerRestrictedSymbols" $ do
        let policy = emptyPolicy{partnerRestrictedSymbols = ["7203.T"]}
        let result = screenOrder True False defaultLimits defaultExposure policy testProposal fixedTime
        result `shouldBe` Left ComplianceRestrictedSymbol

      it "approves when symbol is not restricted" $ do
        let policy = emptyPolicy{restrictedSymbols = ["6758.T"]}
        let result = screenOrder True False defaultLimits defaultExposure policy testProposal fixedTime
        result `shouldBe` Right Approved'

    -- TST-RG-005: within blackout window for symbol → COMPLIANCE_BLACKOUT_ACTIVE
    describe "TST-RG-005: blackout window" $ do
      it "rejects when evaluation time is within the blackout window for the symbol" $ do
        let window =
              BlackoutWindow
                { symbol = "7203.T"
                , startAt = windowStart
                , endAt = windowEnd
                , actionReasonCode = ComplianceOverride
                }
        let policy = emptyPolicy{blackoutWindows = [window]}
        -- fixedTime (2026-01-15) is within windowStart (2026-01-13)..windowEnd (2026-01-17)
        let result = screenOrder True False defaultLimits defaultExposure policy testProposal fixedTime
        result `shouldBe` Left ComplianceBlackoutActive

      it "approves when evaluation time is before the blackout window" $ do
        let window =
              BlackoutWindow
                { symbol = "7203.T"
                , startAt = windowStart
                , endAt = windowEnd
                , actionReasonCode = ComplianceOverride
                }
        let policy = emptyPolicy{blackoutWindows = [window]}
        let result = screenOrder True False defaultLimits defaultExposure policy testProposal beforeWindow
        result `shouldBe` Right Approved'

      it "approves when evaluation time is after the blackout window" $ do
        let window =
              BlackoutWindow
                { symbol = "7203.T"
                , startAt = windowStart
                , endAt = windowEnd
                , actionReasonCode = ComplianceOverride
                }
        let policy = emptyPolicy{blackoutWindows = [window]}
        let result = screenOrder True False defaultLimits defaultExposure policy testProposal afterWindow
        result `shouldBe` Right Approved'

      it "approves when the blackout window is for a different symbol" $ do
        let window =
              BlackoutWindow
                { symbol = "6758.T"
                , startAt = windowStart
                , endAt = windowEnd
                , actionReasonCode = ComplianceOverride
                }
        let policy = emptyPolicy{blackoutWindows = [window]}
        let result = screenOrder True False defaultLimits defaultExposure policy testProposal fixedTime
        result `shouldBe` Right Approved'

    -- TST-RG-008: evaluation context unavailable → RISK_EVALUATION_UNAVAILABLE (fail-closed)
    describe "TST-RG-008: evaluation context unavailable" $ do
      it "returns RiskEvaluationUnavailable when contextAvailable is False" $ do
        let result = screenOrder False False defaultLimits defaultExposure emptyPolicy testProposal fixedTime
        result `shouldBe` Left RiskEvaluationUnavailable

      it "context unavailable takes priority over kill switch" $ do
        let result = screenOrder False True defaultLimits defaultExposure emptyPolicy testProposal fixedTime
        result `shouldBe` Left RiskEvaluationUnavailable

      it "returns Approved when contextAvailable is True and no violations" $ do
        let result = screenOrder True False defaultLimits defaultExposure emptyPolicy testProposal fixedTime
        result `shouldBe` Right Approved'

    -- Kill switch takes priority over risk limits (order of evaluation)
    describe "priority ordering" $ do
      it "kill switch takes priority over risk limit violation" $ do
        let exceededExposure = defaultExposure{dailyLossRate = 0.99}
        let result = screenOrder True True defaultLimits exceededExposure emptyPolicy testProposal fixedTime
        result `shouldBe` Left KillSwitchEnabled

      it "risk limits take priority over restricted symbol" $ do
        let exceededExposure = defaultExposure{dailyLossRate = 0.99}
        let policy = emptyPolicy{restrictedSymbols = ["7203.T"]}
        let result = screenOrder True False defaultLimits exceededExposure policy testProposal fixedTime
        result `shouldBe` Left RiskLimitExceeded

    -- RiskLimitSpecification unit tests (Should)
    describe "RiskLimitSpecification" $ do
      it "is satisfied when all exposure values are below limits" $ do
        isSatisfiedByRiskLimits (RiskLimitSpecification defaultLimits) defaultExposure
          `shouldBe` True

      it "is not satisfied when dailyLossRate equals limit" $ do
        let exposure = defaultExposure{dailyLossRate = 0.05}
        isSatisfiedByRiskLimits (RiskLimitSpecification defaultLimits) exposure
          `shouldBe` False

    -- ComplianceSpecification unit tests (Should)
    describe "ComplianceSpecification" $ do
      it "is satisfied when symbol is not restricted and no active blackout" $ do
        isSatisfiedByCompliance (ComplianceSpecification emptyPolicy) testProposal fixedTime
          `shouldBe` True

      it "is not satisfied when symbol is restricted" $ do
        let policy = emptyPolicy{restrictedSymbols = ["7203.T"]}
        isSatisfiedByCompliance (ComplianceSpecification policy) testProposal fixedTime
          `shouldBe` False
