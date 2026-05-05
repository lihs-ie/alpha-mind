module Domain.AuditLog
  ( -- * Common identifier-like types
    Trace (..)
    -- * Common basic types
  , EventType
  , Service
  , Reason
  ) where

import Data.Text (Text)
import Data.ULID (ULID)

newtype Trace = Trace {value :: ULID}
  deriving stock (Eq, Ord, Show)

type EventType = Text

type Service = Text

type Reason = Text
