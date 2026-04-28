{-# LANGUAGE OverloadedRecordDot #-}
{-# OPTIONS_GHC -fno-hpc #-}

module Persistence.Idempotency (
  IdempotencyRecord (..),
  IdempotencyError (..),
  ReserveResult (..),
  reserveResultForExistingRecord,
  reserveIdempotency,
  completeIdempotency,
) where

import Data.HashMap.Strict qualified as HashMap
import Data.Text qualified as Text
import Data.Time (UTCTime, addUTCTime, getCurrentTime, nominalDay)
import Data.ULID (ULID)
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext,
  FirestoreError (..),
  FromFirestore (fromFirestoreFields),
  ToFirestore (toFirestoreFields),
  ToFirestoreValue (toValue),
  createDocument,
  getDocument,
  requireField,
  upsertDocument,
 )

data IdempotencyRecord = IdempotencyRecord
  { key :: Text.Text
  , identifier :: ULID
  , trace :: ULID
  , service :: Text.Text
  , processedAt :: Maybe UTCTime
  , expiresAt :: UTCTime
  , updatedAt :: UTCTime
  }
  deriving (Show)

instance FromFirestore IdempotencyRecord where
  fromFirestoreFields fields = do
    key <- requireField "key" fields
    identifier <- requireField "identifier" fields
    trace <- requireField "trace" fields
    service <- requireField "service" fields
    processedAt <- requireField "processedAt" fields
    expiresAt <- requireField "expiresAt" fields
    updatedAt <- requireField "updatedAt" fields
    Right
      IdempotencyRecord
        { key = key
        , identifier = identifier
        , trace = trace
        , service = service
        , processedAt = processedAt
        , expiresAt = expiresAt
        , updatedAt = updatedAt
        }

instance ToFirestore IdempotencyRecord where
  toFirestoreFields record =
    HashMap.fromList
      [ ("key", toValue record.key)
      , ("identifier", toValue record.identifier)
      , ("trace", toValue record.trace)
      , ("service", toValue record.service)
      , ("processedAt", toValue record.processedAt)
      , ("expiresAt", toValue record.expiresAt)
      , ("updatedAt", toValue record.updatedAt)
      ]

data IdempotencyError
  = IdempotencyErrorPersistence FirestoreError
  | IdempotencyErrorNotReserved Text.Text
  deriving (Show, Eq)

data ReserveResult
  = Reserved
  | AlreadyReserved
  | AlreadyProcessed
  deriving (Show, Eq)

mkIdempotencyKey :: Text.Text -> ULID -> Text.Text
mkIdempotencyKey service identifier = service <> ":" <> Text.pack (show identifier)

reserveIdempotency ::
  FirestoreContext ->
  Text.Text ->
  ULID ->
  ULID ->
  IO (Either IdempotencyError ReserveResult)
reserveIdempotency context service identifier trace = do
  let idempotencyKey = mkIdempotencyKey service identifier
  now <- getCurrentTime
  result <-
    createDocument
      context
      (CollectionName "idempotency_keys")
      (DocumentId idempotencyKey)
      IdempotencyRecord
        { key = idempotencyKey
        , identifier = identifier
        , trace = trace
        , service = service
        , processedAt = Nothing
        , expiresAt = addUTCTime (30 * nominalDay) now
        , updatedAt = now
        }
  case result of
    Right () -> pure (Right Reserved)
    Left conflict | isAlreadyExists conflict -> resolveExistingReservation context idempotencyKey
    Left firestoreError -> pure . Left $ IdempotencyErrorPersistence firestoreError

resolveExistingReservation ::
  FirestoreContext ->
  Text.Text ->
  IO (Either IdempotencyError ReserveResult)
resolveExistingReservation context idempotencyKey =
  getDocument @IdempotencyRecord context (CollectionName "idempotency_keys") (DocumentId idempotencyKey)
    >>= either
      (pure . Left . IdempotencyErrorPersistence)
      (pure . Right . maybe AlreadyReserved reserveResultForExistingRecord)

reserveResultForExistingRecord :: IdempotencyRecord -> ReserveResult
reserveResultForExistingRecord existing =
  case existing.processedAt of
    Just _ -> AlreadyProcessed
    Nothing -> AlreadyReserved

isAlreadyExists :: FirestoreError -> Bool
isAlreadyExists errorValue =
  case errorValue of
    FirestoreErrorUnexpected 409 _ -> True
    _ -> False

completeIdempotency ::
  FirestoreContext ->
  Text.Text ->
  ULID ->
  IO (Either IdempotencyError ())
completeIdempotency context service identifier = do
  let idempotencyKey = mkIdempotencyKey service identifier
  result <- getDocument @IdempotencyRecord context (CollectionName "idempotency_keys") (DocumentId idempotencyKey)
  case result of
    Left firestoreError -> pure . Left $ IdempotencyErrorPersistence firestoreError
    Right Nothing -> pure . Left $ IdempotencyErrorNotReserved idempotencyKey
    Right (Just existing) -> do
      now <- getCurrentTime
      let completed = existing{processedAt = Just now, updatedAt = now}
      upserted <- upsertDocument context (CollectionName "idempotency_keys") (DocumentId idempotencyKey) completed
      case upserted of
        Left firestoreError -> pure . Left $ IdempotencyErrorPersistence firestoreError
        Right () -> pure (Right ())
