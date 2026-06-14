module Presentation.AppM (
  -- * Application environment
  AppEnv (..),

  -- * Environment construction
  buildAppEnv,
)
where

import Config.Env (optionalTextEnv, requireTextEnv)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Infrastructure.JWT.JwtIssuer (JwtIssuerEnv (..))
import Infrastructure.Repository.FirestoreUserRepository (FirestoreUserRepositoryEnv (..))
import Persistence.Firestore (FirestoreContext (..))

-- ---------------------------------------------------------------------------
-- Application environment
-- ---------------------------------------------------------------------------

-- | Must-09: AppEnv holds all sub-environments needed by BFF handlers.
data AppEnv = AppEnv
  { jwtIssuerEnv :: JwtIssuerEnv
  , userRepositoryEnv :: FirestoreUserRepositoryEnv
  , firestoreContext :: FirestoreContext
  , serviceName :: Text
  }

-- ---------------------------------------------------------------------------
-- Environment construction
-- ---------------------------------------------------------------------------

{- | Must-09: Build 'AppEnv' from environment variables.

Required variables:
  ADMIN_EMAIL           — plaintext admin email (MVP)
  ADMIN_PASSWORD        — plaintext admin password (MVP)
  JWT_SECRET_KEY        — HMAC-SHA256 signing key (at least 32 bytes recommended)
Optional:
  JWT_ISSUER_URL        — iss claim (default \"https://bff.alpha-mind.local\")
  JWT_AUDIENCE_URL      — aud claim (default \"https://bff.alpha-mind.local\")
  JWT_EXPIRY_SECONDS    — token lifetime in seconds (default 3600)
  GCP_PROJECT_ID        — GCP project identifier (default \"alpha-mind-local\")
  FIRESTORE_DATABASE_ID — Firestore database ID (default \"(default)\")
-}
buildAppEnv :: IO AppEnv
buildAppEnv = do
  adminEmailValue <- requireTextEnv "ADMIN_EMAIL"
  adminPasswordValue <- requireTextEnv "ADMIN_PASSWORD"
  secretKeyValue <- requireTextEnv "JWT_SECRET_KEY"
  maybeIssuerUrl <- optionalTextEnv "JWT_ISSUER_URL"
  maybeAudienceUrl <- optionalTextEnv "JWT_AUDIENCE_URL"
  maybeExpirySeconds <- optionalTextEnv "JWT_EXPIRY_SECONDS"
  maybeProjectId <- optionalTextEnv "GCP_PROJECT_ID"
  maybeDatabaseId <- optionalTextEnv "FIRESTORE_DATABASE_ID"
  let issuerUrlValue = fromMaybe "https://bff.alpha-mind.local" maybeIssuerUrl
      audienceUrlValue = fromMaybe "https://bff.alpha-mind.local" maybeAudienceUrl
      expirySecondsValue = maybe 3600 (read . Text.unpack) maybeExpirySeconds
      projectIdValue = fromMaybe "alpha-mind-local" maybeProjectId
      databaseIdValue = fromMaybe "(default)" maybeDatabaseId
  pure
    AppEnv
      { jwtIssuerEnv =
          JwtIssuerEnv
            { secretKey = secretKeyValue
            , issuerUrl = issuerUrlValue
            , audienceUrl = audienceUrlValue
            , expirySeconds = expirySecondsValue
            }
      , userRepositoryEnv =
          FirestoreUserRepositoryEnv
            { adminEmail = adminEmailValue
            , adminPasswordHash = adminPasswordValue
            }
      , firestoreContext =
          FirestoreContext
            { projectId = projectIdValue
            , databaseId = databaseIdValue
            }
      , serviceName = "bff"
      }
