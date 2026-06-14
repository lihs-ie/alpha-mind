{- | Domain logic for insight action validation.

Provides MNPI (Material Non-Public Information) comment filtering used
by the insight action endpoints (adopt, reject, hypothesize).
-}
module Domain.Insight.Action (
  InsightActionError (..),
  checkMnpiFilter,
  mnpiSuspectedKeywords,
)
where

import Data.Text (Text)
import Data.Text qualified as Text

-- ---------------------------------------------------------------------------
-- Error type
-- ---------------------------------------------------------------------------

-- | Reason why an insight action was refused.
newtype InsightActionError
  = -- | The comment contains suspected MNPI keywords.
    MnpiSuspected Text
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------------
-- MNPI filter
-- ---------------------------------------------------------------------------

{- | MVP hard-coded list of MNPI-suspected keywords.

A comment is rejected when it contains any of these terms (case-insensitive).
-}
mnpiSuspectedKeywords :: [Text]
mnpiSuspectedKeywords =
  [ "未公表"
  , "insider"
  , "内部情報"
  , "非公開"
  ]

{- | Check whether a comment contains MNPI-suspected keywords.

Returns 'Left MnpiSuspected' with the matched keyword if any keyword
is found in the comment (case-insensitive), otherwise 'Right ()'.
-}
checkMnpiFilter :: Text -> Either InsightActionError ()
checkMnpiFilter comment =
  let lowercaseComment = Text.toLower comment
      matchedKeyword =
        foldr
          ( \keyword acc ->
              case acc of
                Just _ -> acc
                Nothing ->
                  if Text.isInfixOf (Text.toLower keyword) lowercaseComment
                    then Just keyword
                    else Nothing
          )
          Nothing
          mnpiSuspectedKeywords
   in case matchedKeyword of
        Just keyword -> Left (MnpiSuspected keyword)
        Nothing -> Right ()
