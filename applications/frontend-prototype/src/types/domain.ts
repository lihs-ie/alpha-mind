// ドメイン固有の型定義

export type ScreenState = "initial" | "loading" | "empty" | "error" | "disabled";

export interface AuthSession {
  accessToken: string;
  expiresAt: number;
  user: {
    id: string;
    email: string;
    role: "admin" | "viewer";
    permissions: string[];
  };
}

export interface PnlValue {
  amount: number;
  direction: "profit" | "loss" | "neutral";
}
