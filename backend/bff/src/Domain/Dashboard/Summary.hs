module Domain.Dashboard.Summary (
  RuntimeState (..),
  DashboardSummary (..),
  runtimeStateToText,
)
where

import Data.Text (Text)
import Data.Time (UTCTime)

-- ---------------------------------------------------------------------------
-- Domain types
-- ---------------------------------------------------------------------------

{- | Operational runtime state of the investment pipeline.

Mirrors the @runtimeState@ field in Firestore @operations\/runtime@.
-}
data RuntimeState = Running | Stopped
  deriving stock (Show, Eq)

-- | Convert 'RuntimeState' to the API string representation.
runtimeStateToText :: RuntimeState -> Text
runtimeStateToText Running = "RUNNING"
runtimeStateToText Stopped = "STOPPED"

{- | Must-01: Read model for the @GET \/dashboard\/summary@ endpoint.

Must-05: @pnlToday@, @pnlTotal@, @maxDrawdown@, and @latestSignalAt@ are
MVP placeholders — a dedicated PnL aggregation collection does not yet exist
in the Firestore schema.
-}
data DashboardSummary = DashboardSummary
  { pnlToday :: Double
  -- ^ Intraday PnL (MVP: returns 0.0).
  , pnlTotal :: Double
  -- ^ Total PnL since inception (MVP: returns 0.0).
  , maxDrawdown :: Double
  -- ^ Maximum drawdown percentage (MVP: returns 0.0).
  , runtimeState :: RuntimeState
  -- ^ Live\/stopped state from @operations\/runtime@.
  , killSwitchEnabled :: Bool
  -- ^ Kill-switch flag from @operations\/runtime@.
  , latestSignalAt :: UTCTime
  -- ^ Timestamp of the most recent signal (MVP: returns current time).
  }
