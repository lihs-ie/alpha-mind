module Domain.Compliance.Controls (
  ComplianceControls (..),
  defaultComplianceControls,
)
where

import Data.Text (Text)

-- | Compliance controls read from @compliance_controls\/trading@.
data ComplianceControls = ComplianceControls
  { restrictedSymbols :: [Text]
  , partnerRestrictedSymbols :: [Text]
  , maxCommentLength :: Int
  , autoPromotionEnabled :: Bool
  }

-- | MVP default returned when @compliance_controls\/trading@ document does not exist.
defaultComplianceControls :: ComplianceControls
defaultComplianceControls =
  ComplianceControls
    { restrictedSymbols = []
    , partnerRestrictedSymbols = []
    , maxCommentLength = 120
    , autoPromotionEnabled = False
    }
