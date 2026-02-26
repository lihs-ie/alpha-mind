// OpenAPI スキーマ由来の型定義 (openapi.yaml)

// ===== Enums =====

export type RuntimeState = "RUNNING" | "STOPPED";

export type RuntimeAction = "START" | "STOP";

export type RebalanceFrequency = "daily" | "weekly";

export type Market = "JP";

export type OrderSide = "BUY" | "SELL";

export type OrderStatus =
  | "PROPOSED"
  | "APPROVED"
  | "REJECTED"
  | "EXECUTED"
  | "FAILED";

export type AuditResult = "success" | "failed";

export type ModelStatus = "candidate" | "approved" | "rejected";

export type UserRole = "admin" | "viewer";

export type RunCycleMode = "manual";

export type ReasonCode =
  | "AUTH_INVALID_CREDENTIALS"
  | "AUTH_TOKEN_EXPIRED"
  | "AUTH_FORBIDDEN"
  | "REQUEST_VALIDATION_FAILED"
  | "RESOURCE_NOT_FOUND"
  | "STATE_CONFLICT"
  | "OPERATION_NOT_ALLOWED"
  | "KILL_SWITCH_ENABLED"
  | "RISK_LIMIT_EXCEEDED"
  | "MODEL_NOT_FOUND"
  | "MODEL_NOT_APPROVED"
  | "MODEL_DECISION_INVALID"
  | "DATA_SOURCE_TIMEOUT"
  | "DATA_SOURCE_UNAVAILABLE"
  | "DATA_SCHEMA_INVALID"
  | "DATA_QUALITY_LEAK_DETECTED"
  | "FEATURE_GENERATION_FAILED"
  | "SIGNAL_GENERATION_FAILED"
  | "ORDER_PROPOSAL_FAILED"
  | "EXECUTION_BROKER_TIMEOUT"
  | "EXECUTION_BROKER_REJECTED"
  | "EXECUTION_MARKET_CLOSED"
  | "EXECUTION_INSUFFICIENT_FUNDS"
  | "AUDIT_WRITE_FAILED"
  | "IDEMPOTENCY_DUPLICATE_EVENT"
  | "DEPENDENCY_TIMEOUT"
  | "DEPENDENCY_UNAVAILABLE"
  | "INTERNAL_ERROR";

// ===== Auth =====

export interface LoginRequest {
  email: string;
  password: string;
}

export interface LoginResponse {
  accessToken: string;
  tokenType: string;
  expiresIn: number;
  user: User;
}

export interface User {
  id: string;
  email: string;
  role: UserRole;
  permissions: string[];
}

// ===== Dashboard =====

export interface DashboardSummary {
  pnlToday: number;
  pnlTotal: number;
  maxDrawdown: number;
  runtimeState: RuntimeState;
  killSwitchEnabled: boolean;
  latestSignalAt: string;
}

// ===== Operations =====

export interface RuntimeOperationRequest {
  action: RuntimeAction;
  reason?: string;
}

export interface KillSwitchRequest {
  enabled: boolean;
  reason?: string;
}

export interface RunCycleRequest {
  mode?: RunCycleMode;
}

export interface OperationResult {
  success: boolean;
  traceId: string;
  message?: string;
}

export interface CommandAccepted {
  accepted: boolean;
  commandId: string;
  traceId: string;
}

// ===== Strategy Settings =====

export interface StrategySettings {
  market: Market;
  rebalanceFrequency: RebalanceFrequency;
  symbols: string[];
  dailyLossLimit: number;
  positionConcentrationLimit: number;
  dailyOrderLimit: number;
}

export type StrategySettingsUpdate = StrategySettings;

// ===== Orders =====

export interface OrderSummary {
  orderId: string;
  symbol: string;
  side: OrderSide;
  qty: number;
  status: OrderStatus;
  createdAt: string;
}

export interface OrderDetail extends OrderSummary {
  reasonCode?: ReasonCode;
  traceId?: string;
  brokerOrderId?: string | null;
  updatedAt?: string;
}

export interface OrderListResponse {
  items: OrderSummary[];
  nextCursor?: string | null;
}

export interface ApproveOrderRequest {
  reason?: string;
}

export interface RejectOrderRequest {
  reason: string;
}

// ===== Audit =====

export interface AuditSummary {
  logId: string;
  occurredAt: string;
  eventType: string;
  service: string;
  result: AuditResult;
  traceId: string;
}

export interface AuditDetail extends AuditSummary {
  payload?: Record<string, unknown>;
  reason?: string;
}

export interface AuditListResponse {
  items: AuditSummary[];
  nextCursor?: string | null;
}

// ===== Models =====

export interface ModelMetrics {
  oosReturn: number;
  sharpe: number;
  maxDrawdown: number;
  turnover: number;
  pbo: number;
  dsr: number;
}

export interface ModelValidationSummary {
  modelVersion: string;
  status: ModelStatus;
  createdAt: string;
}

export interface ModelValidationDetail extends ModelValidationSummary {
  metrics: ModelMetrics;
}

export interface ModelValidationListResponse {
  items: ModelValidationSummary[];
}

export interface ModelDecisionRequest {
  reason: string;
}

// ===== Error (RFC 9457 Problem Details) =====

export interface ProblemDetail {
  type: string;
  title: string;
  status: number;
  detail?: string;
  instance?: string;
  traceId?: string;
  reasonCode: ReasonCode;
  retryable?: boolean;
}

// ===== Health =====

export interface HealthResponse {
  status: string;
  time: string;
}

// ===== Query Parameters =====

export interface OrderListParams {
  status?: OrderStatus;
  symbol?: string;
  from?: string;
  to?: string;
  limit?: number;
  cursor?: string;
}

export interface AuditListParams {
  traceId?: string;
  eventType?: string;
  from?: string;
  to?: string;
  limit?: number;
  cursor?: string;
}

export interface ModelValidationListParams {
  status?: ModelStatus;
}
