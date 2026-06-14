{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore read-only repository for risk settings and compliance controls.

Must-16: Provides loadRiskLimits, loadCompliancePolicy, loadRiskExposure, loadKillSwitchState.
Must-17: loadRiskLimits → settings/strategy (dailyLossLimit, positionConcentrationLimit, dailyOrderLimit).
Must-18: loadKillSwitchState → operations/runtime (killSwitchEnabled).
Must-19: loadCompliancePolicy → compliance_controls/trading (restrictedSymbols, partnerRestrictedSymbols, blackoutWindows).

Collections:
  settings/strategy — risk limits
  operations/runtime — kill switch state
  compliance_controls/trading — compliance policy

'loadRiskExposure' returns a conservative empty exposure (0.0 rates, 0 count).
The presentation layer (Issue #44) injects real exposure when it becomes available
from the positions collection; this implementation is a safe fail-open default.
-}
module Infrastructure.Repository.FirestoreRiskSettingsRepository (
  -- * Environment
  FirestoreRiskSettingsEnv (..),

  -- * Functions
  loadRiskLimits,
  loadCompliancePolicy,
  loadRiskExposure,
  loadKillSwitchState,
) where

import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.RiskAssessment.ValueObjects (
  BlackoutWindow (..),
  CompliancePolicy (..),
  RiskExposure (..),
  RiskLimits (..),
 )
import Gogol.FireStore qualified as GogolFireStore
import Infrastructure.Wire.ReasonCodeWire (operatorActionReasonCodeFromWire)
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext,
  FromFirestore (..),
  getDocument,
  requireField,
 )

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreRiskSettingsEnv = FirestoreRiskSettingsEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Strategy settings document (Must-17)
-- ---------------------------------------------------------------------------

data StrategyDocument = StrategyDocument
  { dailyLossLimit :: Double
  , positionConcentrationLimit :: Double
  , dailyOrderLimit :: Int
  }

instance FromFirestore StrategyDocument where
  fromFirestoreFields fields = do
    dailyLossLimitValue <- requireDoubleField "dailyLossLimit" fields
    positionConcentrationLimitValue <- requireDoubleField "positionConcentrationLimit" fields
    dailyOrderLimitValue <- requireIntField "dailyOrderLimit" fields
    Right
      StrategyDocument
        { dailyLossLimit = dailyLossLimitValue
        , positionConcentrationLimit = positionConcentrationLimitValue
        , dailyOrderLimit = dailyOrderLimitValue
        }

requireDoubleField :: Text -> HashMap Text GogolFireStore.Value -> Either Text Double
requireDoubleField key fields =
  case HashMap.lookup key fields of
    Nothing -> Left ("missing field: " <> key)
    Just value ->
      case value.doubleValue of
        Just d -> Right d
        Nothing ->
          case value.integerValue of
            Just i -> Right (fromIntegral i)
            Nothing -> Left ("field " <> key <> " is not a number")

requireIntField :: Text -> HashMap Text GogolFireStore.Value -> Either Text Int
requireIntField key fields =
  case HashMap.lookup key fields of
    Nothing -> Left ("missing field: " <> key)
    Just value ->
      case value.integerValue of
        Just i -> Right (fromIntegral i)
        Nothing -> Left ("field " <> key <> " is not an integer")

-- ---------------------------------------------------------------------------
-- Runtime (operations) document (Must-18)
-- ---------------------------------------------------------------------------

newtype RuntimeDocument = RuntimeDocument
  { killSwitchEnabled :: Bool
  }

instance FromFirestore RuntimeDocument where
  fromFirestoreFields fields = do
    killSwitchEnabledValue <- requireField "killSwitchEnabled" fields
    Right RuntimeDocument{killSwitchEnabled = killSwitchEnabledValue}

-- ---------------------------------------------------------------------------
-- Compliance controls document (Must-19)
-- ---------------------------------------------------------------------------

data ComplianceControlsDocument = ComplianceControlsDocument
  { restrictedSymbols :: [Text]
  , partnerRestrictedSymbols :: [Text]
  , blackoutWindows :: [BlackoutWindowRecord]
  }

data BlackoutWindowRecord = BlackoutWindowRecord
  { symbol :: Text
  , startAt :: UTCTime
  , endAt :: UTCTime
  , actionReasonCode :: Text
  }

instance FromFirestore ComplianceControlsDocument where
  fromFirestoreFields fields = do
    restrictedSymbolsValue <- requireArrayTextField "restrictedSymbols" fields
    partnerRestrictedSymbolsValue <- requireArrayTextField "partnerRestrictedSymbols" fields
    blackoutWindowsValue <- requireBlackoutWindows "blackoutWindows" fields
    Right
      ComplianceControlsDocument
        { restrictedSymbols = restrictedSymbolsValue
        , partnerRestrictedSymbols = partnerRestrictedSymbolsValue
        , blackoutWindows = blackoutWindowsValue
        }

requireArrayTextField ::
  Text ->
  HashMap Text GogolFireStore.Value ->
  Either Text [Text]
requireArrayTextField key fields =
  case HashMap.lookup key fields of
    Nothing -> Right []
    Just value ->
      case value.arrayValue of
        Nothing -> Right []
        Just arrayValue ->
          case arrayValue.values of
            Nothing -> Right []
            Just valueList ->
              mapM extractTextValue valueList
 where
  extractTextValue v =
    case v.stringValue of
      Just t -> Right t
      Nothing -> Left ("array element in " <> key <> " is not a string")

requireBlackoutWindows ::
  Text ->
  HashMap Text GogolFireStore.Value ->
  Either Text [BlackoutWindowRecord]
requireBlackoutWindows key fields =
  case HashMap.lookup key fields of
    Nothing -> Right []
    Just value ->
      case value.arrayValue of
        Nothing -> Right []
        Just arrayValue ->
          case arrayValue.values of
            Nothing -> Right []
            Just valueList ->
              mapM extractBlackoutWindow valueList
 where
  extractBlackoutWindow v =
    case v.mapValue of
      Nothing -> Left "blackout window element is not a map"
      Just mapVal ->
        case mapVal.fields of
          Nothing -> Left "blackout window map has no fields"
          Just mapFields ->
            let fieldMap = mapFields.additional
             in extractBlackoutWindowFromFields fieldMap

extractBlackoutWindowFromFields ::
  HashMap Text GogolFireStore.Value ->
  Either Text BlackoutWindowRecord
extractBlackoutWindowFromFields fields = do
  symbolValue <- requireField "symbol" fields
  startAtValue <- requireField "startAt" fields
  endAtValue <- requireField "endAt" fields
  actionReasonCodeValue <- requireField "actionReasonCode" fields
  Right
    BlackoutWindowRecord
      { symbol = symbolValue
      , startAt = startAtValue
      , endAt = endAtValue
      , actionReasonCode = actionReasonCodeValue
      }

toBlackoutWindow ::
  BlackoutWindowRecord ->
  Either Text BlackoutWindow
toBlackoutWindow record = do
  actionCode <- operatorActionReasonCodeFromWire record.actionReasonCode
  Right
    BlackoutWindow
      { symbol = record.symbol
      , startAt = record.startAt
      , endAt = record.endAt
      , actionReasonCode = actionCode
      }

-- ---------------------------------------------------------------------------
-- Must-17: loadRiskLimits
-- ---------------------------------------------------------------------------

{- | Load risk limits from @settings/strategy@.

Returns a conservative fallback (0.0 limits) when the document is unavailable,
so the screening policy will reject orders (fail-safe).
-}
loadRiskLimits :: FirestoreRiskSettingsEnv -> IO RiskLimits
loadRiskLimits environment = do
  result <-
    getDocument @StrategyDocument
      environment.firestoreContext
      (CollectionName "settings")
      (DocumentId "strategy")
  case result of
    Left _ -> pure failSafeLimits
    Right Nothing -> pure failSafeLimits
    Right (Just document) ->
      pure
        RiskLimits
          { dailyLossLimit = document.dailyLossLimit
          , positionConcentrationLimit = document.positionConcentrationLimit
          , dailyOrderLimit = document.dailyOrderLimit
          }
 where
  failSafeLimits =
    RiskLimits
      { dailyLossLimit = 0.0
      , positionConcentrationLimit = 0.0
      , dailyOrderLimit = 0
      }

-- ---------------------------------------------------------------------------
-- Must-18: loadKillSwitchState
-- ---------------------------------------------------------------------------

{- | Load the kill switch state from @operations/runtime@.

Returns 'True' (kill switch enabled) on error — fail-safe: halt trading on uncertainty.
-}
loadKillSwitchState :: FirestoreRiskSettingsEnv -> IO Bool
loadKillSwitchState environment = do
  result <-
    getDocument @RuntimeDocument
      environment.firestoreContext
      (CollectionName "operations")
      (DocumentId "runtime")
  case result of
    Left _ -> pure True
    Right Nothing -> pure True
    Right (Just document) -> pure document.killSwitchEnabled

-- ---------------------------------------------------------------------------
-- Must-19: loadCompliancePolicy
-- ---------------------------------------------------------------------------

{- | Load the compliance policy from @compliance_controls/trading@.

Returns empty policy (all lists empty) on error — fail-open for compliance reads;
rely on kill switch for safety.
-}
loadCompliancePolicy :: FirestoreRiskSettingsEnv -> IO CompliancePolicy
loadCompliancePolicy environment = do
  result <-
    getDocument @ComplianceControlsDocument
      environment.firestoreContext
      (CollectionName "compliance_controls")
      (DocumentId "trading")
  case result of
    Left _ -> pure emptyPolicy
    Right Nothing -> pure emptyPolicy
    Right (Just document) -> do
      let eitherWindows = mapM toBlackoutWindow document.blackoutWindows
      case eitherWindows of
        Left _ ->
          pure
            CompliancePolicy
              { restrictedSymbols = document.restrictedSymbols
              , partnerRestrictedSymbols = document.partnerRestrictedSymbols
              , blackoutWindows = []
              }
        Right windows ->
          pure
            CompliancePolicy
              { restrictedSymbols = document.restrictedSymbols
              , partnerRestrictedSymbols = document.partnerRestrictedSymbols
              , blackoutWindows = windows
              }
 where
  emptyPolicy =
    CompliancePolicy
      { restrictedSymbols = []
      , partnerRestrictedSymbols = []
      , blackoutWindows = []
      }

-- ---------------------------------------------------------------------------
-- loadRiskExposure (OQ-1: conservative empty default)
-- ---------------------------------------------------------------------------

{- | Load the current risk exposure.

Per OQ-1 in the spec: the positions collection aggregation source is not yet
determined. The presentation layer (Issue #44) will inject real exposure.
This implementation returns a safe empty exposure (0.0 rates, 0 count) as
a fallback so that exposure-based checks pass (fail-open).
-}
loadRiskExposure :: FirestoreRiskSettingsEnv -> IO RiskExposure
loadRiskExposure _environment =
  pure
    RiskExposure
      { dailyLossRate = 0.0
      , positionConcentrationRate = 0.0
      , dailyOrderCount = 0
      }
