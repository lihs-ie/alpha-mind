module Domain.AuditLog.AuditIngestion
  ( -- * Identifier
    AuditIngestionIdentifier (..)
    -- * Value objects
  , TargetEventType (..)
  , DispatchDecision (..)
    -- * Aggregate
  , AuditIngestion (..)
  ) where

import Data.Time (UTCTime)
import Data.ULID (ULID)

import Domain.AuditLog (Trace)
import Domain.AuditLog.ReasonCode (ReasonCode)

newtype AuditIngestionIdentifier = AuditIngestionIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

data TargetEventType
  = AuditRecorded
  deriving stock (Eq, Ord, Show)

data DispatchDecision = DispatchDecision
  { shouldPublish :: Bool
  , targetEventType :: Maybe TargetEventType
  , reasonCode :: Maybe ReasonCode
  }
  deriving stock (Eq, Show)

data AuditIngestion = AuditIngestion
  { identifier :: AuditIngestionIdentifier
  , processed :: Bool
  , processedAt :: Maybe UTCTime
  , trace :: Trace
  , reasonCode :: Maybe ReasonCode
  , dispatchDecision :: Maybe DispatchDecision
  }
  deriving stock (Eq, Show)
