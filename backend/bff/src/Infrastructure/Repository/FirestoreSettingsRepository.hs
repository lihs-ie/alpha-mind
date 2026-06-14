module Infrastructure.Repository.FirestoreSettingsRepository (
  FirestoreSettingsRepositoryEnv (..),
  getStrategySettings,
  getComplianceControls,
)
where

import Data.Int (Int64)
import Data.Text (Text)
import Domain.Compliance.Controls (ComplianceControls (..), defaultComplianceControls)
import Domain.Settings.Strategy (
  RebalanceFrequency (..),
  StrategySettings (..),
  defaultStrategySettings,
 )
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext (..),
  FirestoreError,
  FromFirestore (..),
  requireField,
 )
import Persistence.Firestore qualified as Firestore

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

-- | Environment for reading settings and compliance Firestore collections.
newtype FirestoreSettingsRepositoryEnv = FirestoreSettingsRepositoryEnv
  { firestoreContext :: FirestoreContext
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

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

parseFrequency :: Text -> Either Text RebalanceFrequency
parseFrequency "daily" = Right Daily
parseFrequency "weekly" = Right Weekly
parseFrequency unknown = Left ("Unknown rebalance frequency: " <> unknown)
