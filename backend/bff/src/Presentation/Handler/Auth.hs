{-# LANGUAGE DataKinds #-}

module Presentation.Handler.Auth (
  LoginRequest (..),
  LoginResponse (..),
  UserResponse (..),
  loginHandler,
)
where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (FromJSON (..), ToJSON (..), encode, object, withObject, (.:), (.=))
import Data.Text (Text)
import Domain.Auth.Credential (
  AuthCredential (..),
  AuthPermission (..),
  AuthenticatedUser (..),
  EmailAddress (..),
  PlainPassword (..),
  UserRole (..),
  mkAuthCredential,
 )
import Infrastructure.JWT.JwtIssuer (JwtIssuerEnv (..), issueToken)
import Infrastructure.Repository.FirestoreUserRepository (FirestoreUserRepositoryEnv (..), findUserByEmail)
import Network.HTTP.Types (hContentType)
import Presentation.AppM (AppEnv (..))
import Servant (Handler, ServerError (..), err401, throwError)

-- ---------------------------------------------------------------------------
-- Request / response types
-- ---------------------------------------------------------------------------

data LoginRequest = LoginRequest
  { email :: Text
  , password :: Text
  }

instance FromJSON LoginRequest where
  parseJSON = withObject "LoginRequest" $ \objectValue -> do
    emailValue <- objectValue .: "email"
    passwordValue <- objectValue .: "password"
    pure LoginRequest{email = emailValue, password = passwordValue}

data UserResponse = UserResponse
  { identifier :: Text
  , email :: Text
  , role :: Text
  , permissions :: [Text]
  }

instance ToJSON UserResponse where
  toJSON userResponse =
    object
      [ "identifier" .= userResponse.identifier
      , "email" .= userResponse.email
      , "role" .= userResponse.role
      , "permissions" .= userResponse.permissions
      ]

data LoginResponse = LoginResponse
  { accessToken :: Text
  , tokenType :: Text
  , expiresIn :: Int
  , user :: UserResponse
  }

instance ToJSON LoginResponse where
  toJSON loginResponse =
    object
      [ "accessToken" .= loginResponse.accessToken
      , "tokenType" .= loginResponse.tokenType
      , "expiresIn" .= loginResponse.expiresIn
      , "user" .= loginResponse.user
      ]

-- ---------------------------------------------------------------------------
-- Handler
-- ---------------------------------------------------------------------------

{- | Must-01 + Must-02: POST /auth/login handler.

Returns 200 + JWT on success; 401 problem+json on invalid credentials.
-}
loginHandler :: AppEnv -> LoginRequest -> Handler LoginResponse
loginHandler appEnvironment request = do
  -- Validate input format
  credential <- case mkAuthCredential request.email request.password of
    Left validationError -> throwUnauthorized ("Validation failed: " <> validationError)
    Right credentialValue -> pure credentialValue

  -- Look up user by email
  maybeUser <-
    liftIO $
      findUserByEmail appEnvironment.userRepositoryEnv credential.email

  authenticatedUser <- case maybeUser of
    Nothing -> throwUnauthorized "Invalid credentials"
    Just userValue -> pure userValue

  -- MVP password check: compare plain-text password against stored value
  let userRepositoryEnvironment = appEnvironment.userRepositoryEnv
      storedPassword = userRepositoryEnvironment.adminPasswordHash
      plainPassword = credential.password
      suppliedPassword = unPlainPassword plainPassword
  when (suppliedPassword /= storedPassword) $
    throwUnauthorized "Invalid credentials"

  -- Issue JWT
  let jwtEnvironment = appEnvironment.jwtIssuerEnv
  tokenResult <-
    liftIO $
      issueToken jwtEnvironment authenticatedUser

  tokenText <- case tokenResult of
    Left signingError ->
      throwError
        err401
          { errBody = encode (unauthorizedProblem signingError)
          , errHeaders = [(hContentType, "application/problem+json")]
          , errReasonPhrase = "Unauthorized"
          }
    Right tokenValue -> pure tokenValue

  pure
    LoginResponse
      { accessToken = tokenText
      , tokenType = "Bearer"
      , expiresIn = jwtEnvironment.expirySeconds
      , user = toUserResponse authenticatedUser
      }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | Build a 401 RFC 9457 problem+json response.
throwUnauthorized :: Text -> Handler a
throwUnauthorized detail =
  throwError
    err401
      { errBody = encode (unauthorizedProblem detail)
      , errHeaders = [(hContentType, "application/problem+json")]
      , errReasonPhrase = "Unauthorized"
      }

unauthorizedProblem :: Text -> UnauthorizedProblem
unauthorizedProblem detailText =
  UnauthorizedProblem
    { problemType = "about:blank"
    , title = "Unauthorized"
    , status = 401
    , detail = detailText
    , reasonCode = "AUTH_INVALID_CREDENTIALS"
    }

data UnauthorizedProblem = UnauthorizedProblem
  { problemType :: Text
  , title :: Text
  , status :: Int
  , detail :: Text
  , reasonCode :: Text
  }

instance ToJSON UnauthorizedProblem where
  toJSON problemValue =
    object
      [ "type" .= problemValue.problemType
      , "title" .= problemValue.title
      , "status" .= problemValue.status
      , "detail" .= problemValue.detail
      , "reasonCode" .= problemValue.reasonCode
      ]

toUserResponse :: AuthenticatedUser -> UserResponse
toUserResponse authenticatedUser =
  let emailAddress = authenticatedUser.email
   in UserResponse
        { identifier = authenticatedUser.identifier
        , email = unEmailAddress emailAddress
        , role = userRoleToText authenticatedUser.role
        , permissions = map (.unAuthPermission) authenticatedUser.permissions
        }

userRoleToText :: UserRole -> Text
userRoleToText Admin = "admin"
userRoleToText Viewer = "viewer"
