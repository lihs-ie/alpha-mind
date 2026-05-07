module Domain.AuditLog.ServicePolicy (
  deriveServiceFromEventType,
)
where

import Domain.AuditLog (EventType, Service)

-- | §2.3 Context Map に基づき eventType から発行元サービス名を導出する。
deriveServiceFromEventType :: EventType -> Service
deriveServiceFromEventType = \case
  -- bff 起点
  "market.collect.requested" -> "bff"
  "operation.kill_switch.changed" -> "bff"
  "insight.collect.requested" -> "bff"
  "hypothesis.retest.requested" -> "bff"
  -- data-collector
  "market.collected" -> "data-collector"
  "market.collect.failed" -> "data-collector"
  -- feature-engineering
  "features.generated" -> "feature-engineering"
  "features.generation.failed" -> "feature-engineering"
  -- signal-generator
  "signal.generated" -> "signal-generator"
  "signal.generation.failed" -> "signal-generator"
  -- portfolio-planner
  "orders.proposed" -> "portfolio-planner"
  "orders.proposal.failed" -> "portfolio-planner"
  -- risk-guard
  "orders.approved" -> "risk-guard"
  "orders.rejected" -> "risk-guard"
  -- execution
  "orders.executed" -> "execution"
  "orders.execution.failed" -> "execution"
  "hypothesis.demo.completed" -> "execution"
  -- insight-collector
  "insight.collected" -> "insight-collector"
  "insight.collect.failed" -> "insight-collector"
  -- agent-orchestrator
  "hypothesis.proposed" -> "agent-orchestrator"
  "hypothesis.proposal.failed" -> "agent-orchestrator"
  -- hypothesis-lab
  "hypothesis.backtested" -> "hypothesis-lab"
  "hypothesis.promoted" -> "hypothesis-lab"
  "hypothesis.rejected" -> "hypothesis-lab"
  -- unknown
  _ -> "unknown"
