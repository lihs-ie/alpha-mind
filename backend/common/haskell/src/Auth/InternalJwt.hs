{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-hpc #-}

module Auth.InternalJwt (
  InternalJwtConfig (..),
  JwtError (..),
  JwksCache (..),
  VerifiedPrincipal (..),
  extractBearerToken,
  internalJwtMiddleware,
  jwtErrorToHttpStatus,
  verifiedPrincipalKey,
  verifyInternalJwt,
) where

import App.Response (ToProblemDetails (..), mkErrorResponse, mkProblemDetails)
import Data.Aeson (eitherDecode)
import Data.ByteString (fromStrict)
import Data.Functor (($>))
import Data.IORef (IORef, readIORef, writeIORef)
import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text, stripPrefix)
import Data.Text qualified as Text
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Time (NominalDiffTime, UTCTime, addUTCTime, diffUTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Vault.Lazy qualified as Vault
import Jose.Jwk (JwkSet (..))
import Jose.Jwt (IntDate (..), JwtClaims (jwtAud, jwtExp, jwtIat, jwtIss, jwtSub), JwtContent (..))
import Jose.Jwt qualified as Jwt
import Network.HTTP.Client (Manager, Response (responseBody), httpLbs, newManager, parseRequest)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types (hAuthorization)
import Network.Wai (Middleware, Request (requestHeaders, vault))
import System.IO.Unsafe (unsafePerformIO)

data InternalJwtConfig = InternalJwtConfig
  { expectedAudience :: Text
  , allowedIssuers :: NonEmpty Text
  , jwksUrl :: Text
  , clockSkewSeconds :: Int
  }
  deriving (Show)

data VerifiedPrincipal = VerifiedPrincipal
  { subject :: Text
  , issuer :: Text
  , audience :: Text
  , issuedAt :: UTCTime
  , expiresAt :: UTCTime
  }
  deriving (Show, Eq)

data JwtError
  = TokenMissing
  | TokenMalformed Text
  | SignatureInvalid
  | TokenExpired UTCTime UTCTime
  | AudienceMismatch Text Text
  | IssuerMismatch Text
  | JwksFetchError Text
  deriving (Show, Eq)

data JwksCache = JwksCache
  { cachedAt :: UTCTime
  , jwkSet :: JwkSet
  }

instance ToProblemDetails JwtError where
  toProblemDetails TokenMissing =
    mkProblemDetails "about:blank" "Unauthorized" 401 "Bearer token is missing" "AUTH_TOKEN_MISSING" False
  toProblemDetails (TokenMalformed message) =
    mkProblemDetails "about:blank" "Unauthorized" 401 (Text.unpack message) "AUTH_TOKEN_MALFORMED" False
  toProblemDetails SignatureInvalid =
    mkProblemDetails "about:blank" "Unauthorized" 401 "Signature verification failed" "AUTH_SIGNATURE_INVALID" False
  toProblemDetails (TokenExpired expireAt now) =
    mkProblemDetails
      "about:blank"
      "Unauthorized"
      401
      ("Token expired at " <> show expireAt <> ", current time " <> show now)
      "AUTH_TOKEN_EXPIRED"
      False
  toProblemDetails (AudienceMismatch expected actual) =
    mkProblemDetails
      "about:blank"
      "Forbidden"
      403
      ("Expected audience " <> Text.unpack expected <> ", got " <> Text.unpack actual)
      "AUTH_AUDIENCE_MISMATCH"
      False
  toProblemDetails (IssuerMismatch actual) =
    mkProblemDetails "about:blank" "Forbidden" 403 ("Untrusted issuer: " <> Text.unpack actual) "AUTH_ISSUER_MISMATCH" False
  toProblemDetails (JwksFetchError message) =
    mkProblemDetails "about:blank" "Internal Server Error" 500 (Text.unpack message) "INTERNAL_JWKS_FETCH_ERROR" True

jwtErrorToHttpStatus :: JwtError -> Int
jwtErrorToHttpStatus TokenMissing = 401
jwtErrorToHttpStatus (TokenMalformed _) = 401
jwtErrorToHttpStatus SignatureInvalid = 401
jwtErrorToHttpStatus (TokenExpired _ _) = 401
jwtErrorToHttpStatus (AudienceMismatch _ _) = 403
jwtErrorToHttpStatus (IssuerMismatch _) = 403
jwtErrorToHttpStatus (JwksFetchError _) = 500

verifiedPrincipalKey :: Vault.Key VerifiedPrincipal
verifiedPrincipalKey = unsafePerformIO Vault.newKey
{-# NOINLINE verifiedPrincipalKey #-}

extractBearerToken :: Request -> Either JwtError Text
extractBearerToken request =
  case lookup hAuthorization (requestHeaders request) of
    Nothing -> Left TokenMissing
    Just value ->
      case stripPrefix "Bearer " (decodeUtf8 value) of
        Nothing -> Left (TokenMalformed "Bearer token is malformed")
        Just token
          | Text.null token -> Left (TokenMalformed "Bearer token is empty")
          | otherwise -> Right token

intDateToUTCTime :: IntDate -> UTCTime
intDateToUTCTime (IntDate posix) = posixSecondsToUTCTime posix

validateAudience :: Text -> Text -> Either JwtError ()
validateAudience expected actual =
  if expected == actual then Right () else Left (AudienceMismatch expected actual)

validateIssuers :: NonEmpty Text -> Text -> Either JwtError ()
validateIssuers expecteds actual =
  if actual `elem` expecteds then Right () else Left (IssuerMismatch actual)

validateExpiration :: UTCTime -> Int -> UTCTime -> Either JwtError ()
validateExpiration now clockSkew expireAt =
  if addUTCTime (fromIntegral clockSkew :: NominalDiffTime) expireAt >= now
    then Right ()
    else Left (TokenExpired expireAt now)

validateIssuedAt :: UTCTime -> Int -> UTCTime -> Either JwtError ()
validateIssuedAt now clockSkew issued =
  if addUTCTime (negate (fromIntegral clockSkew)) issued <= now
    then Right ()
    else Left (TokenMalformed "issued in the future")

validateClaims :: InternalJwtConfig -> UTCTime -> JwtClaims -> Either JwtError VerifiedPrincipal
validateClaims config now claims = do
  sub <- maybe (Left (TokenMalformed "missing sub")) Right (jwtSub claims)
  aud <- case jwtAud claims of
    Just [single] -> Right single
    Just _ -> Left (TokenMalformed "multiple audiences not supported")
    Nothing -> Left (TokenMalformed "missing aud")
  iss <- maybe (Left (TokenMalformed "missing iss")) Right (jwtIss claims)
  expire <- maybe (Left (TokenMalformed "missing exp")) Right (jwtExp claims)
  iat <- maybe (Left (TokenMalformed "missing iat")) Right (jwtIat claims)
  validateAudience config.expectedAudience aud
  validateIssuers config.allowedIssuers iss
  validateExpiration now config.clockSkewSeconds (intDateToUTCTime expire)
  validateIssuedAt now config.clockSkewSeconds (intDateToUTCTime iat)
  pure
    VerifiedPrincipal
      { subject = sub
      , issuer = iss
      , audience = aud
      , issuedAt = intDateToUTCTime iat
      , expiresAt = intDateToUTCTime expire
      }

fetchFromEndpoint :: Manager -> Text -> IO (Either JwtError JwkSet)
fetchFromEndpoint manager url = do
  request <- parseRequest (Text.unpack url)
  response <- httpLbs request manager
  pure $ case eitherDecode (responseBody response) of
    Right jwkSetValue -> Right jwkSetValue
    Left err -> Left (JwksFetchError (Text.pack err))

jwksCacheTTL :: NominalDiffTime
jwksCacheTTL = 600

fetchJwkSet :: Manager -> InternalJwtConfig -> IORef (Maybe JwksCache) -> IO (Either JwtError JwkSet)
fetchJwkSet manager config cacheRef = do
  now <- getCurrentTime
  cache <- readIORef cacheRef
  case cache of
    Just value | diffUTCTime now value.cachedAt < jwksCacheTTL -> pure (Right value.jwkSet)
    _ -> do
      result <- fetchFromEndpoint manager config.jwksUrl
      case result of
        Right newJwkSet -> writeIORef cacheRef (Just JwksCache{cachedAt = now, jwkSet = newJwkSet}) $> Right newJwkSet
        Left err -> pure (maybe (Left err) (Right . jwkSet) cache)

verifyInternalJwt ::
  InternalJwtConfig ->
  IORef (Maybe JwksCache) ->
  Text ->
  IO (Either JwtError VerifiedPrincipal)
verifyInternalJwt config cacheRef token =
  newManager tlsManagerSettings >>= \manager -> verifyInternalJwtWithManager manager config cacheRef token

verifyInternalJwtWithManager ::
  Manager ->
  InternalJwtConfig ->
  IORef (Maybe JwksCache) ->
  Text ->
  IO (Either JwtError VerifiedPrincipal)
verifyInternalJwtWithManager manager config cacheRef token = do
  jwksResult <- fetchJwkSet manager config cacheRef
  case jwksResult of
    Left err -> pure (Left err)
    Right jwks -> do
      now <- getCurrentTime
      decoded <- Jwt.decode (keys jwks) Nothing (encodeUtf8 token)
      pure $ case decoded of
        Left _ -> Left SignatureInvalid
        Right (Jws (_header, payload)) -> decodeClaims now payload
        Right (Jwe (_header, payload)) -> decodeClaims now payload
        Right (Unsecured _) -> Left (TokenMalformed "unsecured JWT not allowed")
 where
  decodeClaims now payload =
    case eitherDecode (fromStrict payload) of
      Left err -> Left (TokenMalformed (Text.pack err))
      Right claims -> validateClaims config now claims

internalJwtMiddleware :: InternalJwtConfig -> IORef (Maybe JwksCache) -> Middleware
internalJwtMiddleware config cacheRef app request sendResponse =
  case extractBearerToken request of
    Left err -> sendResponse (mkErrorResponse err)
    Right token ->
      verifyInternalJwt config cacheRef token >>= \case
        Left err -> sendResponse (mkErrorResponse err)
        Right principal ->
          let request' = request{vault = Vault.insert verifiedPrincipalKey principal (vault request)}
           in app request' sendResponse
