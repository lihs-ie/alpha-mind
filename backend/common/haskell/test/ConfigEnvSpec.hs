{-# LANGUAGE OverloadedStrings #-}

module ConfigEnvSpec (spec) where

import Config.Env (CommonRuntimeEnv (..), ConfigError (..), loadCommonRuntimeEnv, optionalTextEnv, requireTextEnv)
import Control.Exception (bracket, try)
import Data.Foldable (traverse_)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "Config.Env" $ do
    it "loads required and optional runtime environment values" $
      withEnvVars
        [ ("PORT", Just "9090")
        , ("GCP_PROJECT_ID", Just "alpha-project")
        , ("GOOGLE_CLOUD_PROJECT", Nothing)
        , ("SERVICE_VERSION", Just "1.2.3")
        , ("K_REVISION", Just "rev-9")
        , ("LOG_LEVEL", Just "error")
        ]
        ( do
            runtime <- loadCommonRuntimeEnv "portfolio"
            port runtime `shouldBe` 9090
            gcpProjectId runtime `shouldBe` "alpha-project"
            serviceName runtime `shouldBe` "portfolio"
            serviceVersion runtime `shouldBe` "1.2.3"
            revision runtime `shouldBe` Just "rev-9"
            logLevel runtime `shouldBe` "error"
        )

    it "uses defaults for optional values" $
      withEnvVars
        [ ("PORT", Nothing)
        , ("GCP_PROJECT_ID", Just "alpha-project")
        , ("GOOGLE_CLOUD_PROJECT", Nothing)
        , ("SERVICE_VERSION", Just "1.2.3")
        , ("K_REVISION", Nothing)
        , ("LOG_LEVEL", Nothing)
        ]
        ( do
            runtime <- loadCommonRuntimeEnv "portfolio"
            port runtime `shouldBe` 8080
            revision runtime `shouldBe` Nothing
            logLevel runtime `shouldBe` "info"
        )

    it "falls back to GOOGLE_CLOUD_PROJECT" $
      withEnvVars
        [ ("PORT", Nothing)
        , ("GCP_PROJECT_ID", Nothing)
        , ("GOOGLE_CLOUD_PROJECT", Just "fallback-project")
        , ("SERVICE_VERSION", Just "1.2.3")
        , ("K_REVISION", Nothing)
        , ("LOG_LEVEL", Just "warning")
        ]
        (gcpProjectId <$> loadCommonRuntimeEnv "portfolio" >>= (`shouldBe` "fallback-project"))

    it "rejects invalid PORT values instead of silently defaulting" $
      withEnvVars
        [ ("PORT", Just "invalid")
        , ("GCP_PROJECT_ID", Just "alpha-project")
        , ("GOOGLE_CLOUD_PROJECT", Nothing)
        , ("SERVICE_VERSION", Just "1.2.3")
        , ("K_REVISION", Nothing)
        , ("LOG_LEVEL", Nothing)
        ]
        (try (loadCommonRuntimeEnv "portfolio") >>= (`shouldBe` Left (InvalidEnv "PORT" "input does not start with a digit")))

    it "rejects invalid LOG_LEVEL values" $
      withEnvVars
        [ ("PORT", Nothing)
        , ("GCP_PROJECT_ID", Just "alpha-project")
        , ("GOOGLE_CLOUD_PROJECT", Nothing)
        , ("SERVICE_VERSION", Just "1.2.3")
        , ("K_REVISION", Nothing)
        , ("LOG_LEVEL", Just "fatal")
        ]
        (try (loadCommonRuntimeEnv "portfolio") >>= (`shouldBe` Left (InvalidEnv "LOG_LEVEL" "fatal")))

    it "exposes requireTextEnv and optionalTextEnv helpers" $
      withEnvVars
        [ ("REQUIRED_TEXT", Just "value")
        , ("OPTIONAL_TEXT", Nothing)
        ]
        ( do
            requireTextEnv "REQUIRED_TEXT" >>= (`shouldBe` "value")
            optionalTextEnv "OPTIONAL_TEXT" >>= (`shouldBe` Nothing)
        )

    it "throws when a required environment variable is missing" $
      withEnvVars
        [ ("PORT", Nothing)
        , ("GCP_PROJECT_ID", Nothing)
        , ("GOOGLE_CLOUD_PROJECT", Nothing)
        , ("SERVICE_VERSION", Just "1.2.3")
        , ("K_REVISION", Nothing)
        , ("LOG_LEVEL", Nothing)
        ]
        (try (loadCommonRuntimeEnv "portfolio") >>= (`shouldBe` Left (MissingEnv "GCP_PROJECT_ID")))

withEnvVars :: [(String, Maybe String)] -> IO a -> IO a
withEnvVars values action =
  bracket
    (traverse (\(name, _) -> (name,) <$> lookupEnv name) values)
    (traverse_ restore)
    (const (traverse_ apply values *> action))
 where
  apply (name, Nothing) = unsetEnv name
  apply (name, Just value) = setEnv name value
  restore (name, Nothing) = unsetEnv name
  restore (name, Just value) = setEnv name value
