module Infrastructure.Repository.FirestoreUserRepository (
  FirestoreUserRepositoryEnv (..),
  findUserByEmail,
)
where

import Data.Text (Text)
import Domain.Auth.Credential (
  AuthPermission (..),
  AuthenticatedUser (..),
  EmailAddress (..),
  UserRole (..),
 )

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

{- | MVP user repository environment.

For MVP there is no dedicated @users@ Firestore collection.  Instead a
single admin user is configured via environment variables.  The
@adminPasswordHash@ field stores the password in plain text for MVP
convenience — this MUST be replaced with a bcrypt hash before going to
production.
-}
data FirestoreUserRepositoryEnv = FirestoreUserRepositoryEnv
  { adminEmail :: Text
  -- ^ Email of the single admin user (from @ADMIN_EMAIL@).
  , adminPasswordHash :: Text
  {- ^ Plain-text password for MVP (from @ADMIN_PASSWORD@).
  Production: store a bcrypt hash here and verify with @bcrypt@.
  -}
  }

-- ---------------------------------------------------------------------------
-- Repository
-- ---------------------------------------------------------------------------

{- | Look up a user by email address.

MVP: only returns the hardcoded admin user when the email matches exactly.
The caller is responsible for verifying the password against the returned
user (see 'Presentation.Handler.Auth.loginHandler').
-}
findUserByEmail ::
  FirestoreUserRepositoryEnv ->
  EmailAddress ->
  IO (Maybe AuthenticatedUser)
findUserByEmail repositoryEnv queryEmail =
  if repositoryEnv.adminEmail == queryEmail.unEmailAddress
    then
      pure
        ( Just
            AuthenticatedUser
              { identifier = "admin-001"
              , email = queryEmail
              , role = Admin
              , permissions =
                  [ AuthPermission "orders:read"
                  , AuthPermission "orders:approve"
                  , AuthPermission "orders:reject"
                  , AuthPermission "settings:write"
                  , AuthPermission "audit:read"
                  ]
              }
        )
    else pure Nothing
