import type {
  User,
  DashboardSummary,
  StrategySettings,
  OrderSummary,
  OrderDetail,
  AuditSummary,
  AuditDetail,
  ModelValidationSummary,
  ModelValidationDetail,
} from "@/types/api";

export const MOCK_USER: User = {
  id: "user-001",
  email: "admin@alpha-mind.local",
  role: "admin",
  permissions: [
    "dashboard:read",
    "operations:write",
    "commands:run",
    "settings:read",
    "settings:write",
    "orders:read",
    "orders:approve",
    "orders:reject",
    "orders:retry",
    "audit:read",
    "models:read",
    "models:decide",
  ],
};

export const MOCK_DASHBOARD: DashboardSummary = {
  pnlToday: 125430.5,
  pnlTotal: 1847290.75,
  maxDrawdown: 3.42,
  runtimeState: "RUNNING",
  killSwitchEnabled: false,
  latestSignalAt: new Date().toISOString(),
};

export const MOCK_STRATEGY: StrategySettings = {
  market: "JP",
  rebalanceFrequency: "daily",
  symbols: ["7203", "6758", "9984", "8306", "6861"],
  dailyLossLimit: 5,
  positionConcentrationLimit: 20,
  dailyOrderLimit: 50,
};

export const MOCK_ORDERS: OrderSummary[] = [
  { orderId: "550e8400-e29b-41d4-a716-446655440001", symbol: "7203", side: "BUY", qty: 100, status: "PROPOSED", createdAt: "2026-02-14T09:30:00Z" },
  { orderId: "550e8400-e29b-41d4-a716-446655440002", symbol: "6758", side: "SELL", qty: 200, status: "APPROVED", createdAt: "2026-02-14T09:28:00Z" },
  { orderId: "550e8400-e29b-41d4-a716-446655440003", symbol: "9984", side: "BUY", qty: 50, status: "EXECUTED", createdAt: "2026-02-14T09:25:00Z" },
  { orderId: "550e8400-e29b-41d4-a716-446655440004", symbol: "8306", side: "SELL", qty: 300, status: "REJECTED", createdAt: "2026-02-14T09:20:00Z" },
  { orderId: "550e8400-e29b-41d4-a716-446655440005", symbol: "6861", side: "BUY", qty: 150, status: "FAILED", createdAt: "2026-02-14T09:15:00Z" },
  { orderId: "550e8400-e29b-41d4-a716-446655440006", symbol: "7203", side: "SELL", qty: 80, status: "PROPOSED", createdAt: "2026-02-14T09:10:00Z" },
  { orderId: "550e8400-e29b-41d4-a716-446655440007", symbol: "6758", side: "BUY", qty: 120, status: "EXECUTED", createdAt: "2026-02-13T15:00:00Z" },
  { orderId: "550e8400-e29b-41d4-a716-446655440008", symbol: "9984", side: "SELL", qty: 90, status: "APPROVED", createdAt: "2026-02-13T14:30:00Z" },
];

export const MOCK_ORDER_DETAILS: Record<string, OrderDetail> = Object.fromEntries(
  MOCK_ORDERS.map((order) => [
    order.orderId,
    {
      ...order,
      traceId: `trc_${order.orderId.slice(-6)}`,
      reasonCode: order.status === "REJECTED" ? "RISK_LIMIT_EXCEEDED" as const : undefined,
      brokerOrderId: order.status === "EXECUTED" ? `BRK-${order.orderId.slice(-4)}` : null,
      updatedAt: order.createdAt,
    },
  ])
);

export const MOCK_AUDIT_LOGS: AuditSummary[] = [
  { logId: "log-001", occurredAt: "2026-02-14T09:30:15Z", eventType: "order.proposed", service: "svc-portfolio-planner", result: "success", traceId: "trc_abc123def456" },
  { logId: "log-002", occurredAt: "2026-02-14T09:28:30Z", eventType: "order.approved", service: "svc-bff", result: "success", traceId: "trc_abc123def457" },
  { logId: "log-003", occurredAt: "2026-02-14T09:25:45Z", eventType: "order.executed", service: "svc-execution", result: "success", traceId: "trc_abc123def458" },
  { logId: "log-004", occurredAt: "2026-02-14T09:20:00Z", eventType: "risk.check", service: "svc-risk-guard", result: "failed", traceId: "trc_abc123def459" },
  { logId: "log-005", occurredAt: "2026-02-14T09:15:30Z", eventType: "signal.generated", service: "svc-signal-generator", result: "success", traceId: "trc_abc123def460" },
  { logId: "log-006", occurredAt: "2026-02-14T09:10:00Z", eventType: "data.collected", service: "svc-data-collector", result: "success", traceId: "trc_abc123def461" },
  { logId: "log-007", occurredAt: "2026-02-14T09:05:00Z", eventType: "feature.generated", service: "svc-feature-engineering", result: "success", traceId: "trc_abc123def462" },
  { logId: "log-008", occurredAt: "2026-02-13T18:00:00Z", eventType: "runtime.started", service: "svc-bff", result: "success", traceId: "trc_abc123def463" },
];

export const MOCK_AUDIT_DETAILS: Record<string, AuditDetail> = Object.fromEntries(
  MOCK_AUDIT_LOGS.map((log) => [
    log.logId,
    {
      ...log,
      payload: { action: log.eventType, timestamp: log.occurredAt, metadata: { source: "mock" } },
      reason: log.result === "failed" ? "リスク制約超過: 1銘柄集中上限を超えています" : undefined,
    },
  ])
);

export const MOCK_MODELS: ModelValidationSummary[] = [
  { modelVersion: "v2.4.0", status: "candidate", createdAt: "2026-02-14T06:00:00Z" },
  { modelVersion: "v2.3.1", status: "approved", createdAt: "2026-02-10T06:00:00Z" },
  { modelVersion: "v2.3.0", status: "rejected", createdAt: "2026-02-07T06:00:00Z" },
  { modelVersion: "v2.2.0", status: "approved", createdAt: "2026-01-28T06:00:00Z" },
];

export const MOCK_MODEL_DETAILS: Record<string, ModelValidationDetail> = {
  "v2.4.0": {
    modelVersion: "v2.4.0",
    status: "candidate",
    createdAt: "2026-02-14T06:00:00Z",
    metrics: { oosReturn: 12.5, sharpe: 1.82, maxDrawdown: 8.3, turnover: 45.2, pbo: 15.0, dsr: 2.14 },
  },
  "v2.3.1": {
    modelVersion: "v2.3.1",
    status: "approved",
    createdAt: "2026-02-10T06:00:00Z",
    metrics: { oosReturn: 10.8, sharpe: 1.65, maxDrawdown: 9.1, turnover: 42.0, pbo: 18.5, dsr: 1.95 },
  },
  "v2.3.0": {
    modelVersion: "v2.3.0",
    status: "rejected",
    createdAt: "2026-02-07T06:00:00Z",
    metrics: { oosReturn: 6.2, sharpe: 0.92, maxDrawdown: 15.7, turnover: 68.3, pbo: 42.0, dsr: 0.85 },
  },
  "v2.2.0": {
    modelVersion: "v2.2.0",
    status: "approved",
    createdAt: "2026-01-28T06:00:00Z",
    metrics: { oosReturn: 9.4, sharpe: 1.48, maxDrawdown: 10.2, turnover: 38.5, pbo: 20.1, dsr: 1.72 },
  },
};
