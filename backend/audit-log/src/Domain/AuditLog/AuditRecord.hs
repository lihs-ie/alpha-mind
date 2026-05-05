module Domain.AuditLog.AuditRecord
  ( -- * Identifiers
    AuditRecordIdentifier (..)
  , SourceEventIdentifier (..)
    -- * Value objects
  , PayloadSummaryValue (..)
  , SourceEventSnapshot (..)
  , ResultNormalization (..)
  , PayloadDigest (..)
    -- * Aggregate
  , AuditRecord (..)
    -- * Domain events
  , DomainEvent (..)
  ) where

import Data.Aeson (Value)
import Data.Map.Strict (Map)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)

import Domain.AuditLog (EventType, Reason, Service, Trace)
import Domain.AuditLog.ReasonCode (ReasonCode)
import Domain.AuditLog.ReasonSource (ReasonSource)
import Domain.AuditLog.Result (Result)
import Domain.AuditLog.Status (Status)

newtype AuditRecordIdentifier = AuditRecordIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

newtype SourceEventIdentifier = SourceEventIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

data PayloadSummaryValue
  = SummaryString Text
  | SummaryNumber Double
  | SummaryBool Bool
  deriving stock (Eq, Show)

data SourceEventSnapshot = SourceEventSnapshot
  { identifier :: SourceEventIdentifier
  , eventType :: EventType
  , occurredAt :: UTCTime
  , trace :: Trace
  , payload :: Value
  }
  deriving stock (Eq, Show)

data ResultNormalization = ResultNormalization
  { result :: Result
  , reason :: Maybe Reason
  , reasonSource :: ReasonSource
  }
  deriving stock (Eq, Show)

data PayloadDigest = PayloadDigest
  { fieldCount :: Int
  , topLevelKeys :: [Text]
  , summary :: Map Text PayloadSummaryValue
  }
  deriving stock (Eq, Show)

data AuditRecord = AuditRecord
  { identifier :: AuditRecordIdentifier
  , eventType :: EventType
  , service :: Service
  , result :: Result
  , trace :: Trace
  , occurredAt :: UTCTime
  , reason :: Maybe Reason
  , payloadSummary :: Maybe (Map Text PayloadSummaryValue)
  , status :: Status
  , reasonCode :: Maybe ReasonCode
  , recordedAt :: Maybe UTCTime
  , sourceEventSnapshot :: SourceEventSnapshot
  , resultNormalization :: ResultNormalization
  , payloadDigest :: Maybe PayloadDigest
  }
  deriving stock (Eq, Show)

data DomainEvent
  = AuditRecordAccepted
      { identifier :: AuditRecordIdentifier
      , eventType :: EventType
      , trace :: Trace
      }
  | AuditRecordPersisted
      { identifier :: AuditRecordIdentifier
      , eventType :: EventType
      , service :: Service
      , result :: Result
      , trace :: Trace
      }
  | AuditRecordPersistenceFailed
      { identifier :: AuditRecordIdentifier
      , reasonCode :: ReasonCode
      , trace :: Trace
      }
  deriving stock (Eq, Show)
