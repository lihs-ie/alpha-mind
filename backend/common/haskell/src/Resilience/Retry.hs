module Resilience.Retry (
  RetryPolicyConfig (..),
  defaultRetryPolicyConfig,
  withRetry,
)
where

import Control.Retry (RetryPolicyM, exponentialBackoff, limitRetries, retrying)

data RetryPolicyConfig = RetryPolicyConfig
  { maxRetries :: Int
  , baseDelayMicros :: Int
  }
  deriving stock (Eq, Show)

defaultRetryPolicyConfig :: RetryPolicyConfig
defaultRetryPolicyConfig =
  RetryPolicyConfig
    { maxRetries = 3
    , baseDelayMicros = 100_000
    }

toRetryPolicy :: RetryPolicyConfig -> RetryPolicyM IO
toRetryPolicy config =
  exponentialBackoff (baseDelayMicros config) <> limitRetries (maxRetries config)

withRetry ::
  RetryPolicyConfig ->
  (e -> Bool) ->
  IO (Either e a) ->
  IO (Either e a)
withRetry config isRetryable action =
  retrying
    (toRetryPolicy config)
    (const (pure . either isRetryable (const False)))
    (const action)
