export const ROUTES = {
  LOGIN: "/login",
  DASHBOARD: "/dashboard",
  STRATEGY_SETTINGS: "/settings/strategy",
  ORDERS: "/orders",
  AUDIT: "/audit",
  MODEL_VALIDATION: "/models/validation",
} as const;

export const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "";

export const API_ROUTES = {
  AUTH_LOGIN: "/auth/login",
  DASHBOARD_SUMMARY: "/dashboard/summary",
  OPERATIONS_RUNTIME: "/operations/runtime",
  OPERATIONS_KILL_SWITCH: "/operations/kill-switch",
  COMMANDS_RUN_CYCLE: "/commands/run-cycle",
  SETTINGS_STRATEGY: "/settings/strategy",
  ORDERS: "/orders",
  ORDER_DETAIL: (orderId: string) => `/orders/${orderId}`,
  ORDER_APPROVE: (orderId: string) => `/orders/${orderId}/approve`,
  ORDER_REJECT: (orderId: string) => `/orders/${orderId}/reject`,
  ORDER_RETRY: (orderId: string) => `/orders/${orderId}/retry`,
  AUDIT: "/audit",
  AUDIT_DETAIL: (logId: string) => `/audit/${logId}`,
  MODELS_VALIDATION: "/models/validation",
  MODEL_VALIDATION_DETAIL: (modelVersion: string) => `/models/validation/${modelVersion}`,
  MODEL_APPROVE: (modelVersion: string) => `/models/validation/${modelVersion}/approve`,
  MODEL_REJECT: (modelVersion: string) => `/models/validation/${modelVersion}/reject`,
} as const;
