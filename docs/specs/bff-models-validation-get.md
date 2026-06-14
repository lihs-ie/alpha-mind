# Spec: GET /models/validation — BFF Service

**Issue**: #70
**Slug**: models-validation-get
**Branch**: feat/bff-models-validation-get
**Status**: implemented

## Must Items

- Must-01: `GET /models/validation` returns 200 with `ModelValidationListResponse` shape `{ items: ModelValidationSummary[], nextCursor: string | null }`
- Must-02: `GET /models/validation/{modelVersion}` returns 200 with `ModelValidationDetail` shape
- Must-03: Missing `Authorization` header → 401 / `AUTH_INVALID_CREDENTIALS`
- Must-04: Invalid/expired token → 401 / `AUTH_INVALID_CREDENTIALS`
- Must-05: Token missing `models:read` permission → 403 / `AUTH_FORBIDDEN`
- Must-06: Unknown `modelVersion` → 404 / `RESOURCE_NOT_FOUND`
- Must-07: Firestore failure → 503 / `DEPENDENCY_UNAVAILABLE`
- Must-08: Default limit 20, max 200, ordered by `createdAt DESC`
- Must-09: `limit` out of range (< 1 or > 200) → 400 / `REQUEST_VALIDATION_FAILED`
- Must-10: `ModelValidationSummary` required fields: `modelVersion`, `status`, `degradationFlag`, `createdAt`
- Must-11: `ModelValidationDetail` required fields: all summary fields + `metrics` (8 numeric fields)
- Must-12: `status` query param validated against enum (`candidate|approved|rejected`); invalid value → 400 / `REQUEST_VALIDATION_FAILED`
- Must-13: `ModelsValidationAPI` wired into `BffAPI` type and `bffServer` in `Presentation.Api`
- Must-14: `cabal build bff` passes; `cabal test bff-test` passes; fourmolu clean; HLint clean

## Should Items

- Should-01: `ModelMetrics` includes all 8 fields: `oosReturn`, `sharpe`, `maxDrawdown`, `turnover`, `pbo`, `dsr`, `costAdjustedReturn`, `slippageAdjustedSharpe`
- Should-02: `degradationFlag` validated against enum (`normal|warn|block`) in Firestore deserialization
- Should-03: `requiresComplianceReview` is optional (`Maybe Bool`)
- Should-04: MVP: status/degradationFlag filters accepted but not applied at Firestore level
- Should-05: Tests for 400 (limit), 400 (status), 404, 503 error paths

## Non-Goals

- Firestore-level status or degradationFlag filtering (MVP: in-memory or unfiltered)
- Cursor-based pagination beyond returning `nextCursor: null`
- Write operations (approve/reject)

## Acceptance Conditions

Error responses conform to RFC 9457 `application/problem+json` with `reasonCode` field.
Authentication: Bearer JWT (HS256), permission: `models:read`.
Firestore collection: `model_registry`, document ID = `modelVersion`.

## Open Questions

- None: error response uses `reasonCode` (not `errorCode`) consistent with all other bff handlers.
