module Infrastructure.JWT.JwtIssuer (
  JwtIssuerEnv (..),
  issueToken,
)
where

import Data.Aeson (encode, object, (.=))
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.ULID (getULID)
import Domain.Auth.Credential (AuthPermission (..), AuthenticatedUser (..), EmailAddress (..), UserRole (..))
import Jose.Jwa (JwsAlg (HS256))
import Jose.Jwk (Jwk (..))
import Jose.Jwt (Jwt (..), JwtEncoding (..), Payload (..))
import Jose.Jwt qualified as Jwt

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

{- | Configuration for the JWT issuer.

'secretKey' is the HMAC-SHA256 signing key read from @JWT_SECRET_KEY@.
-}
data JwtIssuerEnv = JwtIssuerEnv
  { secretKey :: Text
  -- ^ HMAC signing secret from @JWT_SECRET_KEY@.
  , issuerUrl :: Text
  , audienceUrl :: Text
  , expirySeconds :: Int
  }

-- ---------------------------------------------------------------------------
-- Token issuance
-- ---------------------------------------------------------------------------

{- | Sign and return an HS256 JWT for the given authenticated user.

Must-03: HS256 signing.
Must-04: claims iss, aud, sub, email, role, permissions, iat, exp, jti.
Must-05: expiry = 60 min (3600 s).
-}
issueToken :: JwtIssuerEnv -> AuthenticatedUser -> IO (Either Text Text)
issueToken environment authenticatedUser = do
  now <- getPOSIXTime
  ulidValue <- getULID
  let nowInt = floor now :: Int
      expInt = nowInt + environment.expirySeconds
      roleText = userRoleToText authenticatedUser.role
      permissionTexts = map (.unAuthPermission) authenticatedUser.permissions
      emailAddress = authenticatedUser.email
      emailText = unEmailAddress emailAddress
      claimsJson =
        encode $
          object
            [ "iss" .= environment.issuerUrl
            , "aud" .= environment.audienceUrl
            , "sub" .= authenticatedUser.identifier
            , "email" .= emailText
            , "role" .= roleText
            , "permissions" .= permissionTexts
            , "iat" .= nowInt
            , "exp" .= expInt
            , "jti" .= show ulidValue
            ]
      payload = Claims (LazyByteString.toStrict claimsJson)
      symmetricJwk = SymmetricJwk (encodeUtf8 environment.secretKey) Nothing Nothing Nothing
  result <- Jwt.encode [symmetricJwk] (JwsEncoding HS256) payload
  pure $ case result of
    Left jwtError -> Left (Text.pack (show jwtError))
    Right (Jwt tokenBytes) -> Right (decodeUtf8 tokenBytes)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

userRoleToText :: UserRole -> Text
userRoleToText Admin = "admin"
userRoleToText Viewer = "viewer"
