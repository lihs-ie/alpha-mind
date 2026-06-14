# Spec: bff — GET /dashboard/summary (Issue #64)

slug: `dashboard-summary`
service: `bff`
issue: #64

## Must

- Must-01: `GET /dashboard/summary` returns HTTP 200 with JSON body conforming to `DashboardSummary` schema
  - fields: `pnlToday` (number), `pnlTotal` (number), `maxDrawdown` (number), `runtimeState` ("RUNNING"|"STOPPED"), `killSwitchEnabled` (boolean), `latestSignalAt` (date-time string)
- Must-02: Request must include `Authorization: Bearer <jwt>` header; missing or invalid token returns 401 problem+json with `reasonCode: "AUTH_INVALID_CREDENTIALS"`
- Must-03: JWT must contain `dashboard:read` permission; missing permission returns 403 problem+json with `reasonCode: "AUTH_FORBIDDEN"`
- Must-04: `runtimeState` and `killSwitchEnabled` are read from Firestore `operations/runtime` document
- Must-05: MVP — `pnlToday`, `pnlTotal`, `maxDrawdown`, `latestSignalAt` return static defaults (0.0, 0.0, 0.0, current UTC time) as Firestore PnL collection is not yet available
- Must-06: Firestore read failure returns 503 problem+json with `reasonCode: "DEPENDENCY_UNAVAILABLE"`
- Must-07: `operations/runtime` document not found returns hardcoded defaults: `runtimeState: STOPPED`, `killSwitchEnabled: false`
- Must-08: JWT verification uses HS256 with `JWT_SECRET_KEY`; verifies `iss`, `aud`, `exp`
- Must-09: Handler is wired in `Presentation.Api` and reachable from `Main.hs` via `runHttpService`

## Should

- Should-01: JWT verification errors are logged at WARN level

## Non-goal

- Real-time PnL aggregation from positions collection
- Pagination or filtering

## 受入条件

- [ ] `GET /dashboard/summary` with valid JWT returns 200 DashboardSummary
- [ ] Missing Authorization header returns 401
- [ ] Token without `dashboard:read` returns 403
- [ ] Firestore `operations/runtime` fields reflected in response
- [ ] Tests written for handler (WAI integration)
