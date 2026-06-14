module Domain.Settings.Strategy (
  RebalanceFrequency (..),
  StrategySettings (..),
  rebalanceFrequencyToText,
  defaultStrategySettings,
)
where

import Data.Text (Text)

-- | How often the portfolio is rebalanced.
data RebalanceFrequency = Daily | Weekly
  deriving stock (Show, Eq)

-- | Convert 'RebalanceFrequency' to OpenAPI string value.
rebalanceFrequencyToText :: RebalanceFrequency -> Text
rebalanceFrequencyToText Daily = "daily"
rebalanceFrequencyToText Weekly = "weekly"

-- | Strategy configuration read from @settings\/strategy@.
data StrategySettings = StrategySettings
  { market :: Text
  -- ^ Target market (always "JP").
  , rebalanceFrequency :: RebalanceFrequency
  , symbols :: [Text]
  , dailyLossLimit :: Double
  , positionConcentrationLimit :: Double
  , dailyOrderLimit :: Int
  }

-- | MVP default returned when @settings\/strategy@ document does not exist.
defaultStrategySettings :: StrategySettings
defaultStrategySettings =
  StrategySettings
    { market = "JP"
    , rebalanceFrequency = Daily
    , symbols = []
    , dailyLossLimit = 0.0
    , positionConcentrationLimit = 0.0
    , dailyOrderLimit = 1
    }
