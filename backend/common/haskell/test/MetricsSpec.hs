{-# LANGUAGE OverloadedStrings #-}

module MetricsSpec (spec) where

import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.List (isInfixOf)
import Observability.Metrics (getMetrics, initCommonMetrics, observeProcessing, recordDependencyFailure)
import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec =
  describe "Observability.Metrics" $ do
    it "registers and exports common metrics" $ do
      metrics <- initCommonMetrics "common_haskell_spec"
      observeProcessing metrics "success" "none" 0.25
      recordDependencyFailure metrics "firestore" "permission_denied"
      output <- getMetrics
      output `shouldContainText` "common_haskell_spec_requests_total"
      output `shouldContainText` "common_haskell_spec_processing_duration_seconds"
      output `shouldContainText` "common_haskell_spec_dependency_failures_total"
      output `shouldContainText` "dependency=\"firestore\""

    it "returns cached metrics for duplicate service initialization" $ do
      metrics <- initCommonMetrics "common_haskell_spec_duplicate"
      duplicate <- initCommonMetrics "common_haskell_spec_duplicate"
      observeProcessing metrics "success" "none" 0.1
      observeProcessing duplicate "success" "none" 0.1
      output <- getMetrics
      output `shouldContainText` "common_haskell_spec_duplicate_requests_total"

shouldContainText :: LazyChar8.ByteString -> LazyChar8.ByteString -> IO ()
shouldContainText output expected =
  output `shouldSatisfy` isInfixOf (LazyChar8.unpack expected) . LazyChar8.unpack
