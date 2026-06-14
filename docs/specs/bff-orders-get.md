# Spec: bff — GET /orders + GET /orders/{identifier} (Issue #65)

slug: `orders-get`
service: `bff`
issue: #65

## Must

- Must-01: `GET /orders` returns HTTP 200 with `OrderListResponse` JSON (items array + optional nextCursor)
- Must-02: `GET /orders/{identifier}` returns HTTP 200 with `OrderDetail` JSON
- Must-03: Both endpoints require `Authorization: Bearer <jwt>` with `orders:read` permission
- Must-04: Missing/invalid token returns 401 problem+json (`AUTH_INVALID_CREDENTIALS`)
- Must-05: Token lacking `orders:read` returns 403 problem+json (`AUTH_FORBIDDEN`)
- Must-06: Orders read from Firestore `orders` collection ordered by `createdAt DESC`
- Must-07: `GET /orders/{identifier}` returns 404 (`RESOURCE_NOT_FOUND`) when order not found
- Must-08: Firestore failure returns 503 (`DEPENDENCY_UNAVAILABLE`)
- Must-09: `status` and `symbol` query params filter Firestore query when provided
- Must-10: `limit` query param controls page size (default 50, max 200)
- Must-11: MVP — cursor pagination incomplete; `nextCursor` always returns null
- Must-12: Handler wired in `Presentation.Api` and reachable from `Main.hs`

## Should

- Should-01: `from` and `to` date range filters are accepted but not applied in MVP

## Non-goal

- Full cursor pagination implementation
- Joining with `risk_assessments` / `order_executions` for enriched status

## 受入条件

- [ ] `GET /orders` returns 200 with items array
- [ ] Missing Authorization returns 401
- [ ] Token without `orders:read` returns 403
- [ ] Tests written for handler (WAI integration: 401, 403 paths)
