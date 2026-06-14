module Infrastructure.JWT.JwtVerifier (
  JwtVerifierEnv (..),
  VerifiedClaims (..),
  verifyToken,
)
where

import Data.Aeson (FromJSON (..), eitherDecodeStrict, withObject, (.:))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding (encodeUtf8)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Infrastructure.JWT.JwtIssuer (JwtIssuerEnv (..))
import Jose.Jwk (Jwk (..))
import Jose.Jwt (JwtContent (..), JwtError)
import Jose.Jwt qualified as Jwt

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

{- | Verification environment — reuses the same HMAC key as the issuer so
that tokens produced by this BFF instance can be verified here.
-}
newtype JwtVerifierEnv = JwtVerifierEnv {issuerEnv :: JwtIssuerEnv}

-- ---------------------------------------------------------------------------
-- Claims
-- ---------------------------------------------------------------------------

-- | Subset of JWT claims used by BFF handlers.
data VerifiedClaims = VerifiedClaims
  { subject :: Text
  -- ^ @sub@ claim.
  , emailClaim :: Text
  -- ^ @email@ claim.
  , roleClaim :: Text
  -- ^ @role@ claim.
  , permissionClaims :: [Text]
  -- ^ @permissions@ array claim.
  , expiry :: Int
  -- ^ @exp@ UNIX timestamp.
  }

instance FromJSON VerifiedClaims where
  parseJSON = withObject "VerifiedClaims" $ \objectValue -> do
    subjectValue <- objectValue .: "sub"
    emailValue <- objectValue .: "email"
    roleValue <- objectValue .: "role"
    permissionsValue <- objectValue .: "permissions"
    expiryValue <- objectValue .: "exp"
    pure
      VerifiedClaims
        { subject = subjectValue
        , emailClaim = emailValue
        , roleClaim = roleValue
        , permissionClaims = permissionsValue
        , expiry = expiryValue
        }

-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------

{- | Verify a raw Bearer token.

Must-02 / Must-08: checks HS256 signature and expiry.
Returns 'Left' with a human-readable error on failure.
-}
verifyToken :: JwtVerifierEnv -> Text -> IO (Either Text VerifiedClaims)
verifyToken jwtVerifierEnv rawToken = do
  let symmetricJwk =
        SymmetricJwk
          (encodeUtf8 jwtVerifierEnv.issuerEnv.secretKey)
          Nothing
          Nothing
          Nothing
      tokenBytes = encodeUtf8 rawToken
  result <- Jwt.decode [symmetricJwk] Nothing tokenBytes
  case result of
    Left jwtError -> pure . Left $ jwtErrorToText jwtError
    Right (Jws (_, payloadBytes)) -> do
      nowPosix <- getPOSIXTime
      let nowInt = floor nowPosix :: Int
      case eitherDecodeStrict payloadBytes of
        Left parseError -> pure . Left $ Text.pack parseError
        Right claimsValue ->
          if claimsValue.expiry < nowInt
            then pure (Left "Token has expired")
            else pure (Right claimsValue)
    Right _ -> pure (Left "Unexpected JWT encoding — expected JWS")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

jwtErrorToText :: JwtError -> Text
jwtErrorToText jwtError = Text.pack (show jwtError)
