{-# LANGUAGE OverloadedStrings #-}

module App.Response (
  ToProblemDetails (..),
  mkProblemDetails,
  mkErrorResponse,
)
where

import Data.Aeson (ToJSON (..), encode, object, (.=))
import GHC.Generics (Generic)
import Network.HTTP.Types (mkStatus)
import Network.Wai (responseLBS)
import Network.Wai qualified as Wai

data ProblemDetails = ProblemDetails
  { problemType :: String
  , title :: String
  , status :: Int
  , detail :: String
  , reasonCode :: String
  , retryable :: Bool
  }
  deriving stock (Show, Generic)

instance ToJSON ProblemDetails where
  toJSON details =
    object
      [ "type" .= problemType details
      , "title" .= title details
      , "status" .= status details
      , "detail" .= detail details
      , "reasonCode" .= reasonCode details
      , "retryable" .= retryable details
      ]

mkProblemDetails :: String -> String -> Int -> String -> String -> Bool -> ProblemDetails
mkProblemDetails = ProblemDetails

class ToProblemDetails a where
  toProblemDetails :: a -> ProblemDetails

mkErrorResponse :: (ToProblemDetails a) => a -> Wai.Response
mkErrorResponse err =
  let problemDetails = toProblemDetails err
   in responseLBS
        (mkStatus (status problemDetails) "")
        [("Content-Type", "application/problem+json")]
        (encode problemDetails)
