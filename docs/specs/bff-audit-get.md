# Spec: bff — GET /audit + GET /audit/{identifier} (Issue #66)

slug: `audit-get`
service: `bff`
issue: #66

## Must

- Must-01: `GET /audit` returns HTTP 200 with `AuditListResponse` JSON (items array + optional nextCursor)
- Must-02: `GET /audit/{identifier}` returns HTTP 200 with `AuditDetail` JSON
- Must-03: Both endpoints require `Authorization: Bearer <jwt>` with `audit:read` permission
- Must-04: Missing/invalid token returns 401 problem+json (`AUTH_INVALID_CREDENTIALS`)
- Must-05: Token lacking `audit:read` returns 403 problem+json (`AUTH_FORBIDDEN`)
- Must-06: Audit logs read from Firestore `audit_logs` collection ordered by `occurredAt DESC`
- Must-07: `GET /audit/{identifier}` returns 404 (`RESOURCE_NOT_FOUND`) when log not found
- Must-08: Firestore failure returns 503 (`DEPENDENCY_UNAVAILABLE`)
- Must-09: `limit` controls page size (default 50, max 200)
- Must-10: MVP — `trace` and `eventType` filters are accepted but not applied
- Must-11: Handler wired in `Presentation.Api` and reachable from `Main.hs`

## Non-goal

- Filtering by trace or eventType in Firestore query (MVP)
- Full cursor pagination

## 受入条件

- [ ] `GET /audit` returns 200 with items array
- [ ] Missing Authorization returns 401
- [ ] Token without `audit:read` returns 403
- [ ] Tests written for handler (WAI integration: 401, 403 paths)
