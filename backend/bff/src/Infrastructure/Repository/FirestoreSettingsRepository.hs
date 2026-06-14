module Infrastructure.Repository.FirestoreSettingsRepository (
  FirestoreSettingsRepositoryEnv (..),
  StrategySettingsUpdate (..),
  ComplianceControlsUpdate (..),
  StoredStrategySettings (..),
  StoredComplianceControls (..),
  getStrategySettings,
  getStoredStrategySettings,
  getComplianceControls,
  getStoredComplianceControls,
  updateStrategySettings,
  updateComplianceControls,
)
where

import Data.HashMap.Strict qualified as HashMap
import Data.Int (Int64)
import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.Compliance.Controls (ComplianceControls (..), defaultComplianceControls)
import Domain.Settings.Strategy (
  RebalanceFrequency (..),
  StrategySettings (..),
  defaultStrategySettings,
  rebalanceFrequencyToText,
 )
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext (..),
  FirestoreError,
  FromFirestore (..),
  FromFirestoreValue (..),
  ToFirestore (..),
  ToFirestoreValue (..),
  requireField,
 )
import Persistence.Firestore qualified as Firestore

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

-- | Environment for reading and writing settings and compliance Firestore collections.
newtype FirestoreSettingsRepositoryEnv = FirestoreSettingsRepositoryEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Stored records (includes version for optimistic locking)
-- ---------------------------------------------------------------------------

-- | Strategy settings read from Firestore, including the version counter.
data StoredStrategySettings = StoredStrategySettings
  { settings :: StrategySettings
  , version :: Int
  }

-- | Compliance controls read from Firestore, including the version counter.
data StoredComplianceControls = StoredComplianceControls
  { controls :: ComplianceControls
  , version :: Int
  }

-- ---------------------------------------------------------------------------
-- Update types
-- ---------------------------------------------------------------------------

-- | Data for writing strategy settings to @settings\/strategy@.
data StrategySettingsUpdate = StrategySettingsUpdate
  { settings :: StrategySettings
  , updatedBy :: Text
  , updatedAt :: UTCTime
  , version :: Int
  }

-- | Data for writing compliance controls to @compliance_controls\/trading@.
data ComplianceControlsUpdate = ComplianceControlsUpdate
  { controls :: ComplianceControls
  , updatedBy :: Text
  , updatedAt :: UTCTime
  , version :: Int
  }

-- ---------------------------------------------------------------------------
-- FromFirestore instances
-- ---------------------------------------------------------------------------

instance FromFirestore StrategySettings where
  fromFirestoreFields fieldMap = do
    marketValue <- requireField "market" fieldMap
    frequencyText <- requireField "rebalanceFrequency" fieldMap
    frequencyValue <- parseFrequency frequencyText
    dailyLossInt <- requireField "dailyLossLimit" fieldMap :: Either Text Int64
    concentrationInt <- requireField "positionConcentrationLimit" fieldMap :: Either Text Int64
    orderLimitInt <- requireField "dailyOrderLimit" fieldMap :: Either Text Int64
    pure
      StrategySettings
        { market = marketValue
        , rebalanceFrequency = frequencyValue
        , -- MVP: array decoding not supported by current FromFirestoreValue instances;
          -- symbols are returned from defaultStrategySettings or need a bespoke decoder.
          symbols = []
        , dailyLossLimit = fromIntegral dailyLossInt
        , positionConcentrationLimit = fromIntegral concentrationInt
        , dailyOrderLimit = fromIntegral orderLimitInt
        }

instance FromFirestore ComplianceControls where
  fromFirestoreFields fieldMap = do
    maxCommentInt <- requireField "maxCommentLength" fieldMap :: Either Text Int64
    autoPromotionValue <- requireField "autoPromotionEnabled" fieldMap
    pure
      ComplianceControls
        { -- MVP: array decoding not supported by current FromFirestoreValue instances;
          -- symbol arrays returned as empty lists.
          restrictedSymbols = []
        , partnerRestrictedSymbols = []
        , maxCommentLength = fromIntegral maxCommentInt
        , autoPromotionEnabled = autoPromotionValue
        }

instance FromFirestore StoredStrategySettings where
  fromFirestoreFields fieldMap = do
    settingsValue <- fromFirestoreFields fieldMap
    let versionValue = case HashMap.lookup "version" fieldMap of
          Nothing -> 0
          Just fieldValue ->
            case extractValue "version" fieldValue :: Either Text Int64 of
              Left _ -> 0
              Right integerValue -> fromIntegral integerValue
    pure StoredStrategySettings{settings = settingsValue, version = versionValue}

instance FromFirestore StoredComplianceControls where
  fromFirestoreFields fieldMap = do
    controlsValue <- fromFirestoreFields fieldMap
    let versionValue = case HashMap.lookup "version" fieldMap of
          Nothing -> 0
          Just fieldValue ->
            case extractValue "version" fieldValue :: Either Text Int64 of
              Left _ -> 0
              Right integerValue -> fromIntegral integerValue
    pure StoredComplianceControls{controls = controlsValue, version = versionValue}

-- ---------------------------------------------------------------------------
-- ToFirestore instances
-- ---------------------------------------------------------------------------

instance ToFirestore StrategySettingsUpdate where
  toFirestoreFields settingsUpdate =
    HashMap.fromList
      [ ("market", toValue settingsUpdate.settings.market)
      , ("rebalanceFrequency", toValue (rebalanceFrequencyToText settingsUpdate.settings.rebalanceFrequency))
      , ("dailyLossLimit", toValue (round settingsUpdate.settings.dailyLossLimit :: Int64))
      , ("positionConcentrationLimit", toValue (round settingsUpdate.settings.positionConcentrationLimit :: Int64))
      , ("dailyOrderLimit", toValue (fromIntegral settingsUpdate.settings.dailyOrderLimit :: Int64))
      , ("updatedBy", toValue settingsUpdate.updatedBy)
      , ("updatedAt", toValue settingsUpdate.updatedAt)
      , ("version", toValue (fromIntegral settingsUpdate.version :: Int64))
      ]

instance ToFirestore ComplianceControlsUpdate where
  toFirestoreFields controlsUpdate =
    HashMap.fromList
      [ ("maxCommentLength", toValue (fromIntegral controlsUpdate.controls.maxCommentLength :: Int64))
      , ("autoPromotionEnabled", toValue controlsUpdate.controls.autoPromotionEnabled)
      , ("updatedBy", toValue controlsUpdate.updatedBy)
      , ("updatedAt", toValue controlsUpdate.updatedAt)
      , ("version", toValue (fromIntegral controlsUpdate.version :: Int64))
      ]

-- ---------------------------------------------------------------------------
-- Repository operations
-- ---------------------------------------------------------------------------

{- | Get strategy settings from @settings\/strategy@.

Returns 'defaultStrategySettings' when the document does not exist.
-}
getStrategySettings ::
  FirestoreSettingsRepositoryEnv ->
  IO (Either FirestoreError StrategySettings)
getStrategySettings settingsRepositoryEnv = do
  resultValue <-
    Firestore.getDocument
      settingsRepositoryEnv.firestoreContext
      (CollectionName "settings")
      (DocumentId "strategy")
  pure $ case resultValue of
    Left firestoreError -> Left firestoreError
    Right Nothing -> Right defaultStrategySettings
    Right (Just settingsValue) -> Right settingsValue

{- | Get strategy settings with version counter from @settings\/strategy@.

Returns 'defaultStrategySettings' with version 0 when the document does not
exist.
-}
getStoredStrategySettings ::
  FirestoreSettingsRepositoryEnv ->
  IO (Either FirestoreError StoredStrategySettings)
getStoredStrategySettings settingsRepositoryEnv = do
  resultValue <-
    Firestore.getDocument
      settingsRepositoryEnv.firestoreContext
      (CollectionName "settings")
      (DocumentId "strategy")
  pure $ case resultValue of
    Left firestoreError -> Left firestoreError
    Right Nothing ->
      Right
        StoredStrategySettings
          { settings = defaultStrategySettings
          , version = 0
          }
    Right (Just storedValue) -> Right storedValue

{- | Get compliance controls from @compliance_controls\/trading@.

Returns 'defaultComplianceControls' when the document does not exist.
-}
getComplianceControls ::
  FirestoreSettingsRepositoryEnv ->
  IO (Either FirestoreError ComplianceControls)
getComplianceControls settingsRepositoryEnv = do
  resultValue <-
    Firestore.getDocument
      settingsRepositoryEnv.firestoreContext
      (CollectionName "compliance_controls")
      (DocumentId "trading")
  pure $ case resultValue of
    Left firestoreError -> Left firestoreError
    Right Nothing -> Right defaultComplianceControls
    Right (Just controlsValue) -> Right controlsValue

{- | Get compliance controls with version counter from @compliance_controls\/trading@.

Returns 'defaultComplianceControls' with version 0 when the document does not
exist.
-}
getStoredComplianceControls ::
  FirestoreSettingsRepositoryEnv ->
  IO (Either FirestoreError StoredComplianceControls)
getStoredComplianceControls settingsRepositoryEnv = do
  resultValue <-
    Firestore.getDocument
      settingsRepositoryEnv.firestoreContext
      (CollectionName "compliance_controls")
      (DocumentId "trading")
  pure $ case resultValue of
    Left firestoreError -> Left firestoreError
    Right Nothing ->
      Right
        StoredComplianceControls
          { controls = defaultComplianceControls
          , version = 0
          }
    Right (Just storedValue) -> Right storedValue

-- | Write updated strategy settings to @settings\/strategy@.
updateStrategySettings ::
  FirestoreSettingsRepositoryEnv ->
  StrategySettingsUpdate ->
  IO (Either FirestoreError ())
updateStrategySettings settingsRepositoryEnv settingsUpdate =
  Firestore.upsertDocument
    settingsRepositoryEnv.firestoreContext
    (CollectionName "settings")
    (DocumentId "strategy")
    settingsUpdate

-- | Write updated compliance controls to @compliance_controls\/trading@.
updateComplianceControls ::
  FirestoreSettingsRepositoryEnv ->
  ComplianceControlsUpdate ->
  IO (Either FirestoreError ())
updateComplianceControls settingsRepositoryEnv controlsUpdate =
  Firestore.upsertDocument
    settingsRepositoryEnv.firestoreContext
    (CollectionName "compliance_controls")
    (DocumentId "trading")
    controlsUpdate

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

parseFrequency :: Text -> Either Text RebalanceFrequency
parseFrequency "daily" = Right Daily
parseFrequency "weekly" = Right Weekly
parseFrequency unknown = Left ("Unknown rebalance frequency: " <> unknown)
