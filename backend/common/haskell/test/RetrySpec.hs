module RetrySpec (spec) where

import Data.Functor (($>))
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Resilience.Retry (RetryPolicyConfig (..), defaultRetryPolicyConfig, withRetry)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "Resilience.Retry" $ do
    it "returns successful results without retrying" $ do
      counter <- newIORef 0
      result <- withRetry noDelayPolicy (const True) (counted counter (Right "ok"))
      result `shouldBe` Right "ok"
      readIORef counter >>= (`shouldBe` 1)

    it "retries retryable failures until success" $ do
      counter <- newIORef 0
      result <-
        withRetry
          noDelayPolicy
          (== "retry")
          ( do
              attempt <- increment counter
              pure (if attempt < 3 then Left "retry" else Right "ok")
          )
      result `shouldBe` Right "ok"
      readIORef counter >>= (`shouldBe` 3)

    it "does not retry non-retryable failures" $ do
      counter <- newIORef 0
      result <- withRetry noDelayPolicy (== "retry") (counted counter (Left "fatal"))
      result `shouldBe` Left "fatal"
      readIORef counter >>= (`shouldBe` 1)

    it "returns the final retryable failure after max retries" $ do
      counter <- newIORef 0
      result <- withRetry noDelayPolicy (== "retry") (counted counter (Left "retry"))
      result `shouldBe` Left "retry"
      readIORef counter >>= (`shouldBe` 4)

    it "defines the documented default policy" $
      defaultRetryPolicyConfig
        `shouldBe` RetryPolicyConfig{maxRetries = 3, baseDelayMicros = 100_000}

noDelayPolicy :: RetryPolicyConfig
noDelayPolicy =
  RetryPolicyConfig{maxRetries = 3, baseDelayMicros = 0}

counted :: IORef Int -> Either String String -> IO (Either String String)
counted counter result =
  increment counter $> result

increment :: IORef Int -> IO Int
increment counter =
  modifyIORef' counter (+ 1) *> readIORef counter
