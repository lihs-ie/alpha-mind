module Domain.Operation.ControlSpec (spec) where

import Domain.Dashboard.Summary (RuntimeState (..))
import Domain.Operation.Control (
  RuntimeAction (..),
  RuntimeTransitionError (..),
  applyKillSwitch,
  validateRuntimeTransition,
 )
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "Domain.Operation.Control" $ do
  describe "validateRuntimeTransition" $ do
    it "START from STOPPED returns Running (valid transition)" $
      validateRuntimeTransition Stopped Start `shouldBe` Right Running

    it "STOP from RUNNING returns Stopped (valid transition)" $
      validateRuntimeTransition Running Stop `shouldBe` Right Stopped

    it "START from RUNNING returns StateConflict (invalid: already RUNNING)" $
      validateRuntimeTransition Running Start
        `shouldBe` Left (StateConflict "already RUNNING")

    it "STOP from STOPPED returns StateConflict (invalid: already STOPPED)" $
      validateRuntimeTransition Stopped Stop
        `shouldBe` Left (StateConflict "already STOPPED")

  describe "applyKillSwitch" $ do
    it "enabled=True always succeeds (idempotent toggle)" $
      applyKillSwitch True `shouldBe` applyKillSwitch True

    it "enabled=False always succeeds (idempotent toggle)" $
      applyKillSwitch False `shouldBe` applyKillSwitch False
