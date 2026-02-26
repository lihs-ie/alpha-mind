import { API_BASE_URL } from "@/constants/routes";
import type { ProblemDetail } from "@/types/api";
import type { ScreenId } from "@/constants/screenIds";
import type { ActionId } from "@/constants/actionIds";
import { ApiError } from "@/types/errors";
import { getAccessToken } from "./authToken";
import { generateTraceId } from "./traceId";

interface RequestOptions {
  method?: "GET" | "POST" | "PUT" | "DELETE";
  body?: unknown;
  screenId?: ScreenId;
  actionId?: ActionId;
  params?: Record<string, string | number | undefined>;
}

function buildUrl(path: string, params?: Record<string, string | number | undefined>): string {
  const url = new URL(`${API_BASE_URL}${path}`, window.location.origin);
  if (params) {
    for (const [key, value] of Object.entries(params)) {
      if (value !== undefined && value !== "") {
        url.searchParams.set(key, String(value));
      }
    }
  }
  return url.toString();
}

export async function apiClient<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { method = "GET", body, screenId, actionId, params } = options;

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };

  const token = getAccessToken();
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  const traceId = generateTraceId();
  headers["X-Trace-Id"] = traceId;

  if (screenId) {
    headers["X-Screen-Id"] = screenId;
  }
  if (actionId) {
    headers["X-Action-Id"] = actionId;
  }

  const url = buildUrl(path, params);

  const response = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!response.ok) {
    let problem: ProblemDetail;
    try {
      problem = await response.json();
    } catch {
      problem = {
        type: "about:blank",
        title: response.statusText,
        status: response.status,
        reasonCode: "INTERNAL_ERROR",
        retryable: response.status >= 500,
      };
    }
    throw new ApiError(problem);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return response.json();
}
