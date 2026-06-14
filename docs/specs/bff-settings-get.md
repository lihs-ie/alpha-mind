# Spec: bff — GET /settings/strategy + GET /compliance/controls (Issue #67)

slug: `settings-get`
service: `bff`
issue: #67

## Must

- Must-01: `GET /settings/strategy` returns HTTP 200 with `StrategySettingsResponse` JSON
- Must-02: `GET /compliance/controls` returns HTTP 200 with `ComplianceControlsResponse` JSON
- Must-03: `GET /settings/strategy` requires `Authorization: Bearer <jwt>` with `settings:read` permission
- Must-04: `GET /compliance/controls` requires `Authorization: Bearer <jwt>` with `compliance:read` permission
- Must-05: Missing/invalid token returns 401 problem+json (`AUTH_INVALID_CREDENTIALS`)
- Must-06: Token lacking required permission returns 403 problem+json (`AUTH_FORBIDDEN`)
- Must-07: Strategy settings read from Firestore `settings/strategy`; default returned when document not found
- Must-08: Compliance controls read from Firestore `compliance_controls/trading`; default returned when not found
- Must-09: Firestore failure returns 503 (`DEPENDENCY_UNAVAILABLE`)
- Must-10: MVP — `symbols`, `restrictedSymbols`, `partnerRestrictedSymbols`, `blackoutWindows`, `sourcePolicies` returned as `[]`
- Must-11: Both handlers wired in `Presentation.Api` and reachable from `Main.hs`

## Non-goal

- Array field decoding from Firestore (MVP — no `[a]` instance in `FromFirestoreValue`)
- Mutation endpoints (POST/PUT/DELETE)

## 受入条件

- [ ] `GET /settings/strategy` returns 200 with strategy fields
- [ ] `GET /compliance/controls` returns 200 with compliance fields
- [ ] Missing Authorization returns 401
- [ ] Token without required permission returns 403
- [ ] Tests written for both handlers (WAI integration: 401, 403 paths)
