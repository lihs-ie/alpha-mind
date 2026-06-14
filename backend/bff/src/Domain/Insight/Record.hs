module Domain.Insight.Record (
  InsightSourceType (..),
  InsightSignalClass (..),
  InsightSentiment (..),
  InsightSummary (..),
  InsightDetail (..),
  insightSourceTypeToText,
  insightSignalClassToText,
  insightSentimentToText,
)
where

import Data.Text (Text)
import Data.Time (UTCTime)

-- | Source type of an insight record.
data InsightSourceType
  = InsightSourceTypeX
  | InsightSourceTypeYouTube
  | InsightSourceTypePaper
  | InsightSourceTypeGitHub
  deriving stock (Show, Eq)

-- | Convert 'InsightSourceType' to OpenAPI string value.
insightSourceTypeToText :: InsightSourceType -> Text
insightSourceTypeToText InsightSourceTypeX = "x"
insightSourceTypeToText InsightSourceTypeYouTube = "youtube"
insightSourceTypeToText InsightSourceTypePaper = "paper"
insightSourceTypeToText InsightSourceTypeGitHub = "github"

-- | Signal class of an insight record.
data InsightSignalClass
  = InsightSignalClassStructuralAnomaly
  | InsightSignalClassEventNoise
  deriving stock (Show, Eq)

-- | Convert 'InsightSignalClass' to OpenAPI string value.
insightSignalClassToText :: InsightSignalClass -> Text
insightSignalClassToText InsightSignalClassStructuralAnomaly = "structural_anomaly"
insightSignalClassToText InsightSignalClassEventNoise = "event_noise"

-- | Sentiment of an insight record.
data InsightSentiment
  = InsightSentimentPositive
  | InsightSentimentNeutral
  | InsightSentimentNegative
  deriving stock (Show, Eq)

-- | Convert 'InsightSentiment' to OpenAPI string value.
insightSentimentToText :: InsightSentiment -> Text
insightSentimentToText InsightSentimentPositive = "positive"
insightSentimentToText InsightSentimentNeutral = "neutral"
insightSentimentToText InsightSentimentNegative = "negative"

-- | Read model for insight record list items.
data InsightSummary = InsightSummary
  { identifier :: Text
  , sourceType :: InsightSourceType
  , summary :: Text
  , sourceUrl :: Text
  , collectedAt :: UTCTime
  , signalClass :: InsightSignalClass
  , soWhatScore :: Double
  , skillVersion :: Maybe Text
  }

-- | Extended insight record detail including evidence and theme.
data InsightDetail = InsightDetail
  { identifier :: Text
  , sourceType :: InsightSourceType
  , summary :: Text
  , sourceUrl :: Text
  , collectedAt :: UTCTime
  , signalClass :: InsightSignalClass
  , soWhatScore :: Double
  , skillVersion :: Maybe Text
  , evidenceSnippet :: Text
  , theme :: Maybe Text
  , sentiment :: Maybe InsightSentiment
  , trace :: Maybe Text
  }
