module Observability.Metrics (
  CommonMetrics (..),
  initCommonMetrics,
  observeProcessing,
  recordDependencyFailure,
  getMetrics,
) where

import Data.ByteString.Lazy (ByteString)
import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Time (NominalDiffTime)
import Prometheus (
  Counter,
  Histogram,
  Info (..),
  Label1,
  Label2,
  Vector,
  counter,
  defaultBuckets,
  exportMetricsAsText,
  histogram,
  incCounter,
  observe,
  register,
  vector,
  withLabel,
 )
import System.IO.Unsafe (unsafePerformIO)

data CommonMetrics = CommonMetrics
  { requestsTotal :: Vector Label1 Counter
  , processingDurationSeconds :: Vector Label2 Histogram
  , dependencyFailuresTotal :: Vector Label2 Counter
  }

initCommonMetrics :: Text -> IO CommonMetrics
initCommonMetrics serviceName =
  HashMap.lookup serviceName <$> readIORef metricsCache >>= maybe registerAndCache pure
 where
  registerAndCache = do
    metrics <- registerCommonMetrics serviceName
    atomicModifyIORef' metricsCache (\cache -> (HashMap.insert serviceName metrics cache, ()))
    pure metrics

metricsCache :: IORef (HashMap Text CommonMetrics)
metricsCache = unsafePerformIO (newIORef HashMap.empty)
{-# NOINLINE metricsCache #-}

registerCommonMetrics :: Text -> IO CommonMetrics
registerCommonMetrics serviceName = do
  requestTotal <-
    register $
      vector ("result" :: Text) $
        counter (Info (serviceName <> "_requests_total") "Total requests")
  dependencyFailuresTotal <-
    register $
      vector ("dependency", "reason_code") $
        counter (Info (serviceName <> "_dependency_failures_total") "Dependency failures")
  processingDurationSeconds <-
    register $
      vector ("result", "reason_code") $
        histogram
          (Info (serviceName <> "_processing_duration_seconds") "Processing duration")
          defaultBuckets
  pure
    CommonMetrics
      { requestsTotal = requestTotal
      , dependencyFailuresTotal = dependencyFailuresTotal
      , processingDurationSeconds = processingDurationSeconds
      }

observeProcessing :: CommonMetrics -> Text -> Text -> NominalDiffTime -> IO ()
observeProcessing metrics result reasonCode duration = do
  withLabel (requestsTotal metrics) result incCounter
  withLabel
    (processingDurationSeconds metrics)
    (result, reasonCode)
    (`observe` realToFrac duration)

recordDependencyFailure :: CommonMetrics -> Text -> Text -> IO ()
recordDependencyFailure metrics dependency reasonCode = do
  withLabel (dependencyFailuresTotal metrics) (dependency, reasonCode) incCounter
getMetrics :: IO ByteString
getMetrics = exportMetricsAsText
