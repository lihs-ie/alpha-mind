export const SCREEN_IDS = {
  LOGIN: "SCR-000",
  DASHBOARD: "SCR-001",
  STRATEGY_SETTINGS: "SCR-002",
  ORDERS: "SCR-003",
  AUDIT: "SCR-004",
  MODEL_VALIDATION: "SCR-005",
} as const;

export type ScreenId = typeof SCREEN_IDS[keyof typeof SCREEN_IDS];
