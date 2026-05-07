module Domain.AuditLog.ServicePolicySpec (spec) where

import Domain.AuditLog.ServicePolicy (deriveServiceFromEventType)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "Domain.AuditLog.ServicePolicy" $ do
    describe "deriveServiceFromEventType" $ do
      -- bff
      it "maps market.collect.requested to bff" $
        deriveServiceFromEventType "market.collect.requested" `shouldBe` "bff"

      it "maps operation.kill_switch.changed to bff" $
        deriveServiceFromEventType "operation.kill_switch.changed" `shouldBe` "bff"

      it "maps insight.collect.requested to bff" $
        deriveServiceFromEventType "insight.collect.requested" `shouldBe` "bff"

      it "maps hypothesis.retest.requested to bff" $
        deriveServiceFromEventType "hypothesis.retest.requested" `shouldBe` "bff"

      -- data-collector
      it "maps market.collected to data-collector" $
        deriveServiceFromEventType "market.collected" `shouldBe` "data-collector"

      it "maps market.collect.failed to data-collector" $
        deriveServiceFromEventType "market.collect.failed" `shouldBe` "data-collector"

      -- feature-engineering
      it "maps features.generated to feature-engineering" $
        deriveServiceFromEventType "features.generated" `shouldBe` "feature-engineering"

      it "maps features.generation.failed to feature-engineering" $
        deriveServiceFromEventType "features.generation.failed" `shouldBe` "feature-engineering"

      -- signal-generator
      it "maps signal.generated to signal-generator" $
        deriveServiceFromEventType "signal.generated" `shouldBe` "signal-generator"

      it "maps signal.generation.failed to signal-generator" $
        deriveServiceFromEventType "signal.generation.failed" `shouldBe` "signal-generator"

      -- portfolio-planner
      it "maps orders.proposed to portfolio-planner" $
        deriveServiceFromEventType "orders.proposed" `shouldBe` "portfolio-planner"

      it "maps orders.proposal.failed to portfolio-planner" $
        deriveServiceFromEventType "orders.proposal.failed" `shouldBe` "portfolio-planner"

      -- risk-guard
      it "maps orders.approved to risk-guard" $
        deriveServiceFromEventType "orders.approved" `shouldBe` "risk-guard"

      it "maps orders.rejected to risk-guard" $
        deriveServiceFromEventType "orders.rejected" `shouldBe` "risk-guard"

      -- execution
      it "maps orders.executed to execution" $
        deriveServiceFromEventType "orders.executed" `shouldBe` "execution"

      it "maps orders.execution.failed to execution" $
        deriveServiceFromEventType "orders.execution.failed" `shouldBe` "execution"

      it "maps hypothesis.demo.completed to execution" $
        deriveServiceFromEventType "hypothesis.demo.completed" `shouldBe` "execution"

      -- insight-collector
      it "maps insight.collected to insight-collector" $
        deriveServiceFromEventType "insight.collected" `shouldBe` "insight-collector"

      it "maps insight.collect.failed to insight-collector" $
        deriveServiceFromEventType "insight.collect.failed" `shouldBe` "insight-collector"

      -- agent-orchestrator
      it "maps hypothesis.proposed to agent-orchestrator" $
        deriveServiceFromEventType "hypothesis.proposed" `shouldBe` "agent-orchestrator"

      it "maps hypothesis.proposal.failed to agent-orchestrator" $
        deriveServiceFromEventType "hypothesis.proposal.failed" `shouldBe` "agent-orchestrator"

      -- hypothesis-lab
      it "maps hypothesis.backtested to hypothesis-lab" $
        deriveServiceFromEventType "hypothesis.backtested" `shouldBe` "hypothesis-lab"

      it "maps hypothesis.promoted to hypothesis-lab" $
        deriveServiceFromEventType "hypothesis.promoted" `shouldBe` "hypothesis-lab"

      it "maps hypothesis.rejected to hypothesis-lab" $
        deriveServiceFromEventType "hypothesis.rejected" `shouldBe` "hypothesis-lab"

      -- unknown
      it "maps unknown event types to unknown" $
        deriveServiceFromEventType "some.random.event" `shouldBe` "unknown"

      it "maps empty string to unknown" $
        deriveServiceFromEventType "" `shouldBe` "unknown"
