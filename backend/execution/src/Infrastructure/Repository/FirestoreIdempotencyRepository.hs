{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of the idempotency repository for the execution service.

Must-01/11/12/22: FirestoreIdempotencyRepositoryT newtype wrapping ReaderT.
Service name is "execution" — the shared Persistence.Idempotency primitive builds
the key as "execution:{identifier}" internally.
-}
module Infrastructure.Repository.FirestoreIdempotencyRepository (
  -- * Environment
  FirestoreIdempotencyEnv (..),

  -- * Monad transformer
  FirestoreIdempotencyRepositoryT (..),
  runFirestoreIdempotencyRepositoryT,

  -- * Idempotency operations
  reserveExecutionIdempotency,
  completeExecutionIdempotency,
) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Text (Text)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.Aggregate (OrderExecutionIdentifier (..))
import Persistence.Firestore (FirestoreContext)
import Persistence.Idempotency (IdempotencyError, ReserveResult, completeIdempotency, reserveIdempotency)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

data FirestoreIdempotencyEnv = FirestoreIdempotencyEnv
  { firestoreContext :: FirestoreContext
  , serviceName :: Text
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreIdempotencyRepositoryT m a = FirestoreIdempotencyRepositoryT
  { unFirestoreIdempotencyRepositoryT :: ReaderT FirestoreIdempotencyEnv m a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO)

runFirestoreIdempotencyRepositoryT ::
  FirestoreIdempotencyEnv ->
  FirestoreIdempotencyRepositoryT m a ->
  m a
runFirestoreIdempotencyRepositoryT environment action =
  runReaderT (unFirestoreIdempotencyRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Idempotency operations
-- ---------------------------------------------------------------------------

{- | Reserve an idempotency key for an execution event.

Delegates to 'Persistence.Idempotency.reserveIdempotency' using the configured
service name (typically "execution").
-}
reserveExecutionIdempotency ::
  OrderExecutionIdentifier ->
  Trace ->
  FirestoreIdempotencyRepositoryT IO (Either IdempotencyError ReserveResult)
reserveExecutionIdempotency executionIdentifier trace = FirestoreIdempotencyRepositoryT $ do
  environment <- ask
  liftIO $
    reserveIdempotency
      environment.firestoreContext
      environment.serviceName
      executionIdentifier.value
      trace.value

{- | Mark an idempotency key as completed after processing.

Delegates to 'Persistence.Idempotency.completeIdempotency' using the configured
service name (typically "execution").
-}
completeExecutionIdempotency ::
  OrderExecutionIdentifier ->
  FirestoreIdempotencyRepositoryT IO (Either IdempotencyError ())
completeExecutionIdempotency executionIdentifier = FirestoreIdempotencyRepositoryT $ do
  environment <- ask
  liftIO $
    completeIdempotency
      environment.firestoreContext
      environment.serviceName
      executionIdentifier.value
