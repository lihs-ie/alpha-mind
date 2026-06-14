module Domain.Auth.Credential (
  -- * Value objects
  EmailAddress (..),
  PlainPassword (..),
  AuthCredential (..),

  -- * Smart constructors
  mkAuthCredential,

  -- * Authorization model
  UserRole (..),
  AuthPermission (..),
  AuthenticatedUser (..),
)
where

import Data.Text (Text)
import Data.Text qualified as Text

-- ---------------------------------------------------------------------------
-- Value objects
-- ---------------------------------------------------------------------------

-- | A validated email address.  Must contain '@'.
newtype EmailAddress = EmailAddress {unEmailAddress :: Text}
  deriving stock (Show, Eq)

-- | A plaintext password.  Must not be empty.
newtype PlainPassword = PlainPassword {unPlainPassword :: Text}
  deriving stock (Show, Eq)

-- | Combined credential supplied by the user at login time.
data AuthCredential = AuthCredential
  { email :: EmailAddress
  , password :: PlainPassword
  }
  deriving stock (Show, Eq)

-- ---------------------------------------------------------------------------
-- Smart constructor
-- ---------------------------------------------------------------------------

{- | Validate raw text inputs and produce an 'AuthCredential', or an error.

Rules:
  * email must contain '@'
  * password must not be empty
-}
mkAuthCredential :: Text -> Text -> Either Text AuthCredential
mkAuthCredential rawEmail rawPassword = do
  validatedEmail <-
    if Text.isInfixOf "@" rawEmail
      then Right (EmailAddress rawEmail)
      else Left "Invalid email address: must contain '@'"
  validatedPassword <-
    if Text.null rawPassword
      then Left "Password must not be empty"
      else Right (PlainPassword rawPassword)
  Right AuthCredential{email = validatedEmail, password = validatedPassword}

-- ---------------------------------------------------------------------------
-- Authorization model
-- ---------------------------------------------------------------------------

data UserRole = Admin | Viewer
  deriving stock (Show, Eq)

-- | A permission string (e.g. \"orders:approve\").
newtype AuthPermission = AuthPermission {unAuthPermission :: Text}
  deriving stock (Show, Eq)

-- | An authenticated and authorised user principal.
data AuthenticatedUser = AuthenticatedUser
  { identifier :: Text
  , email :: EmailAddress
  , role :: UserRole
  , permissions :: [AuthPermission]
  }
  deriving stock (Show, Eq)
