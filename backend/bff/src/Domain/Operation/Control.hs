module Domain.Operation.Control (
  KillSwitchState (..),
  RuntimeAction (..),
  RuntimeTransitionError (..),
  RuntimeState (..),
  validateRuntimeTransition,
  applyKillSwitch,
) where

import Data.Text (Text)
import Domain.Dashboard.Summary (RuntimeState (..))

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

data KillSwitchState = KillSwitchDisabled | KillSwitchEnabled
  deriving stock (Show, Eq)

data RuntimeAction = Start | Stop
  deriving stock (Show, Eq)

data RuntimeTransitionError
  = StateConflict Text
  | OperationNotAllowed Text
  deriving stock (Show, Eq)

-- ---------------------------------------------------------------------------
-- Transition logic
-- ---------------------------------------------------------------------------

validateRuntimeTransition ::
  RuntimeState ->
  RuntimeAction ->
  Either RuntimeTransitionError RuntimeState
validateRuntimeTransition Running Start = Left (StateConflict "already RUNNING")
validateRuntimeTransition Stopped Stop = Left (StateConflict "already STOPPED")
validateRuntimeTransition _ Start = Right Running
validateRuntimeTransition _ Stop = Right Stopped

applyKillSwitch :: Bool -> KillSwitchState
applyKillSwitch True = KillSwitchEnabled
applyKillSwitch False = KillSwitchDisabled
