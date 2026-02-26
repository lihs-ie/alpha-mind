import { http, HttpResponse, delay } from "msw";
import {
  MOCK_USER,
  MOCK_DASHBOARD,
  MOCK_STRATEGY,
  MOCK_ORDERS,
  MOCK_ORDER_DETAILS,
  MOCK_AUDIT_LOGS,
  MOCK_AUDIT_DETAILS,
  MOCK_MODELS,
  MOCK_MODEL_DETAILS,
} from "./data";

const API_BASE = "/api";

let dashboardState = { ...MOCK_DASHBOARD };
let strategyState = { ...MOCK_STRATEGY };
let ordersState = [...MOCK_ORDERS];

export const handlers = [
  // Auth
  http.post(`${API_BASE}/auth/login`, async ({ request }) => {
    await delay(500);
    const body = await request.json() as { email: string; password: string };

    if (body.email === "admin@alpha-mind.local" && body.password === "password") {
      return HttpResponse.json({
        accessToken: "mock-jwt-token-" + Date.now(),
        tokenType: "Bearer",
        expiresIn: 3600,
        user: MOCK_USER,
      });
    }

    return HttpResponse.json(
      {
        type: "about:blank",
        title: "Unauthorized",
        status: 401,
        detail: "Invalid credentials",
        reasonCode: "AUTH_INVALID_CREDENTIALS",
        retryable: false,
      },
      { status: 401, headers: { "Content-Type": "application/problem+json" } }
    );
  }),

  // Dashboard
  http.get(`${API_BASE}/dashboard/summary`, async () => {
    await delay(300);
    return HttpResponse.json({
      ...dashboardState,
      latestSignalAt: new Date().toISOString(),
    });
  }),

  // Runtime Operations
  http.post(`${API_BASE}/operations/runtime`, async ({ request }) => {
    await delay(400);
    const body = await request.json() as { action: string };
    dashboardState.runtimeState = body.action === "START" ? "RUNNING" : "STOPPED";
    return HttpResponse.json({
      success: true,
      traceId: "trc_" + Date.now().toString(36),
    });
  }),

  // Kill Switch
  http.post(`${API_BASE}/operations/kill-switch`, async ({ request }) => {
    await delay(400);
    const body = await request.json() as { enabled: boolean };
    dashboardState.killSwitchEnabled = body.enabled;
    return HttpResponse.json({
      success: true,
      traceId: "trc_" + Date.now().toString(36),
    });
  }),

  // Run Cycle
  http.post(`${API_BASE}/commands/run-cycle`, async () => {
    await delay(300);
    return HttpResponse.json(
      {
        accepted: true,
        commandId: crypto.randomUUID(),
        traceId: "trc_" + Date.now().toString(36),
      },
      { status: 202 }
    );
  }),

  // Strategy Settings
  http.get(`${API_BASE}/settings/strategy`, async () => {
    await delay(300);
    return HttpResponse.json(strategyState);
  }),

  http.put(`${API_BASE}/settings/strategy`, async ({ request }) => {
    await delay(500);
    const body = await request.json() as typeof strategyState;
    strategyState = body;
    return HttpResponse.json({
      success: true,
      traceId: "trc_" + Date.now().toString(36),
    });
  }),

  // Orders
  http.get(`${API_BASE}/orders`, async ({ request }) => {
    await delay(300);
    const url = new URL(request.url);
    const status = url.searchParams.get("status");
    const symbol = url.searchParams.get("symbol");

    let filtered = [...ordersState];
    if (status) filtered = filtered.filter((order) => order.status === status);
    if (symbol) filtered = filtered.filter((order) => order.symbol.includes(symbol.toUpperCase()));

    return HttpResponse.json({
      items: filtered,
      nextCursor: null,
    });
  }),

  http.get(`${API_BASE}/orders/:orderId`, async ({ params }) => {
    await delay(200);
    const detail = MOCK_ORDER_DETAILS[params.orderId as string];
    if (!detail) {
      return HttpResponse.json(
        { type: "about:blank", title: "Not Found", status: 404, reasonCode: "RESOURCE_NOT_FOUND", retryable: false },
        { status: 404 }
      );
    }
    return HttpResponse.json(detail);
  }),

  http.post(`${API_BASE}/orders/:orderId/approve`, async ({ params }) => {
    await delay(400);
    const orderId = params.orderId as string;
    ordersState = ordersState.map((order) =>
      order.orderId === orderId ? { ...order, status: "APPROVED" as const } : order
    );
    if (MOCK_ORDER_DETAILS[orderId]) {
      MOCK_ORDER_DETAILS[orderId] = { ...MOCK_ORDER_DETAILS[orderId], status: "APPROVED" };
    }
    return HttpResponse.json({ success: true, traceId: "trc_" + Date.now().toString(36) });
  }),

  http.post(`${API_BASE}/orders/:orderId/reject`, async ({ params }) => {
    await delay(400);
    const orderId = params.orderId as string;
    ordersState = ordersState.map((order) =>
      order.orderId === orderId ? { ...order, status: "REJECTED" as const } : order
    );
    if (MOCK_ORDER_DETAILS[orderId]) {
      MOCK_ORDER_DETAILS[orderId] = { ...MOCK_ORDER_DETAILS[orderId], status: "REJECTED" };
    }
    return HttpResponse.json({ success: true, traceId: "trc_" + Date.now().toString(36) });
  }),

  http.post(`${API_BASE}/orders/:orderId/retry`, async () => {
    await delay(300);
    return HttpResponse.json(
      { accepted: true, commandId: crypto.randomUUID(), traceId: "trc_" + Date.now().toString(36) },
      { status: 202 }
    );
  }),

  // Audit Logs
  http.get(`${API_BASE}/audit`, async ({ request }) => {
    await delay(300);
    const url = new URL(request.url);
    const traceId = url.searchParams.get("traceId");
    const eventType = url.searchParams.get("eventType");

    let filtered = [...MOCK_AUDIT_LOGS];
    if (traceId) filtered = filtered.filter((log) => log.traceId.includes(traceId));
    if (eventType) filtered = filtered.filter((log) => log.eventType.includes(eventType));

    return HttpResponse.json({ items: filtered, nextCursor: null });
  }),

  http.get(`${API_BASE}/audit/:logId`, async ({ params }) => {
    await delay(200);
    const detail = MOCK_AUDIT_DETAILS[params.logId as string];
    if (!detail) {
      return HttpResponse.json(
        { type: "about:blank", title: "Not Found", status: 404, reasonCode: "RESOURCE_NOT_FOUND", retryable: false },
        { status: 404 }
      );
    }
    return HttpResponse.json(detail);
  }),

  // Model Validation
  http.get(`${API_BASE}/models/validation`, async ({ request }) => {
    await delay(300);
    const url = new URL(request.url);
    const status = url.searchParams.get("status");

    let filtered = [...MOCK_MODELS];
    if (status) filtered = filtered.filter((model) => model.status === status);

    return HttpResponse.json({ items: filtered });
  }),

  http.get(`${API_BASE}/models/validation/:modelVersion`, async ({ params }) => {
    await delay(200);
    const detail = MOCK_MODEL_DETAILS[params.modelVersion as string];
    if (!detail) {
      return HttpResponse.json(
        { type: "about:blank", title: "Not Found", status: 404, reasonCode: "MODEL_NOT_FOUND", retryable: false },
        { status: 404 }
      );
    }
    return HttpResponse.json(detail);
  }),

  http.post(`${API_BASE}/models/validation/:modelVersion/approve`, async ({ params }) => {
    await delay(400);
    const version = params.modelVersion as string;
    if (MOCK_MODEL_DETAILS[version]) {
      MOCK_MODEL_DETAILS[version] = { ...MOCK_MODEL_DETAILS[version], status: "approved" };
    }
    return HttpResponse.json({ success: true, traceId: "trc_" + Date.now().toString(36) });
  }),

  http.post(`${API_BASE}/models/validation/:modelVersion/reject`, async ({ params }) => {
    await delay(400);
    const version = params.modelVersion as string;
    if (MOCK_MODEL_DETAILS[version]) {
      MOCK_MODEL_DETAILS[version] = { ...MOCK_MODEL_DETAILS[version], status: "rejected" };
    }
    return HttpResponse.json({ success: true, traceId: "trc_" + Date.now().toString(36) });
  }),
];
