const TOKEN_KEY = "alpha_mind_token";

let cachedToken: string | null | undefined;

export function getAccessToken(): string | null {
  if (typeof window === "undefined") return null;
  if (cachedToken !== undefined) return cachedToken;
  cachedToken = sessionStorage.getItem(TOKEN_KEY);
  return cachedToken;
}

export function setAccessToken(token: string): void {
  sessionStorage.setItem(TOKEN_KEY, token);
  cachedToken = token;
}

export function removeAccessToken(): void {
  sessionStorage.removeItem(TOKEN_KEY);
  cachedToken = null;
}

export function isTokenExpired(expiresAt: number): boolean {
  const CLOCK_SKEW_SECONDS = 60;
  return Date.now() >= (expiresAt - CLOCK_SKEW_SECONDS) * 1000;
}
