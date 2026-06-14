# Spec: bff — GET /hypotheses + GET /hypotheses/{identifier} (Issue #69)

slug: `hypotheses-get`
service: `bff`
issue: #69

## Goal

`svc-bff` に `GET /hypotheses`（仮説一覧）と `GET /hypotheses/{identifier}`（仮説詳細）を追加する。
Firestore `hypothesis_registry` コレクションから読み取り、JWT 認証 + `hypotheses:read` 権限チェックを行う。
既存の `Presentation.Handler.Insights` および `Presentation.Handler.Audit` と同一パターンで実装する。

## Must (満たさなければ done でない)

- [ ] Must-01: `GET /hypotheses` が HTTP 200 と `HypothesisListResponse` JSON (`{ "items": [...], "nextCursor": string | null }`) を返す
- [ ] Must-02: `GET /hypotheses/{identifier}` が HTTP 200 と `HypothesisDetail` JSON を返す
- [ ] Must-03: 両エンドポイントとも `Authorization: Bearer <jwt>` ヘッダが必須で、`hypotheses:read` パーミッションを保持するトークンのみ受理する
- [ ] Must-04: トークン欠如 / 不正トークンで 401 `application/problem+json` (`"errorCode":"AUTH_INVALID_CREDENTIALS"`) を返す
- [ ] Must-05: `hypotheses:read` パーミッションを持たないトークンで 403 `application/problem+json` (`"errorCode":"AUTH_FORBIDDEN"`) を返す
- [ ] Must-06: `GET /hypotheses/{identifier}` で `hypothesis_registry` にドキュメントが存在しない場合、404 `application/problem+json` (`"errorCode":"RESOURCE_NOT_FOUND"`) を返す
- [ ] Must-07: Firestore 障害時に 503 `application/problem+json` (`"errorCode":"DEPENDENCY_UNAVAILABLE"`) を返す
- [ ] Must-08: `GET /hypotheses` は `hypothesis_registry` コレクションをデフォルトで `updatedAt DESC` 順に取得し、デフォルト上限 30 件・最大 200 件とする
- [ ] Must-09: `limit` クエリパラメータが 1〜200 の範囲外の値のとき 400 `application/problem+json` (`"errorCode":"VALIDATION_ERROR"`) を返す
- [ ] Must-10: `HypothesisSummary` レスポンスに必須フィールド (`identifier`, `symbol`, `instrumentType`, `status`, `title`, `updatedAt`) が全て含まれる
- [ ] Must-11: `HypothesisDetail` レスポンスに `HypothesisSummary` の全フィールドに加えて必須フィールド (`sourceEvidence`, `skillVersion`, `instructionProfileVersion`) が含まれる
- [ ] Must-12: `status` クエリパラメータ (`draft|backtested|demo|live|rejected`) はパースされ型チェックされる（不正な値で 400 を返す）
- [ ] Must-13: ハンドラが `Presentation.Handler.Hypotheses` モジュールとして実装され、`Presentation.Api` の `BffAPI` 型および `bffServer` に結線され、`Main.hs` から到達可能である
- [ ] Must-14: `backend/bff` が `cabal build all` を通過し、`hlint backend/bff/` および `fourmolu --mode check` が警告・エラー 0 で pass する

## Should (望ましいが必須でない)

- Should-01: `status` クエリパラメータによる Firestore サーバーサイドフィルタを実装する（複合インデックス `(status ASC, updatedAt DESC)` を使用。MVP では受付のみ可）
- Should-02: `cursor` を用いた真のカーソルページネーションを実装する（MVP では `nextCursor: null` 固定でも可）
- Should-03: `HypothesisDetail` のオプションフィールド (`costAdjustedReturn`, `dsr`, `pbo`, `demoPeriod`, `insiderRisk`, `requiresComplianceReview`, `mnpiSelfDeclared`, `autoPromotionEligible`, `promotionMode`, `latestFailureSummary`) を、Firestore ドキュメントに存在する場合はレスポンスに含める
- Should-04: ドメイン型 `Domain.Hypothesis.Record` の `HypothesisSummary` / `HypothesisDetail` を新規作成し、ハンドラはドメイン型を介してレスポンス変換する
- Should-05: ユニットテスト (`backend/bff/test/Presentation/Handler/HypothesesSpec.hs`) で 401 / 403 / 404 / 503 / 400 パスを hspec で assert する

## 受入条件 (acceptance — Must の確認方法)

- Must-01: `curl -s -H "Authorization: Bearer <valid_jwt_hypotheses_read>" http://localhost:8080/hypotheses` が HTTP 200 かつ `{"items":[...],"nextCursor":...}` を返す（`items` は配列型、`nextCursor` は文字列または null）
- Must-02: `curl -s -H "Authorization: Bearer <valid_jwt_hypotheses_read>" http://localhost:8080/hypotheses/<ulid>` が HTTP 200 かつ `sourceEvidence`・`skillVersion`・`instructionProfileVersion` フィールドを含む JSON を返す
- Must-03: 有効な `hypotheses:read` トークンでのみ 200 を返し、`insights:read` のみ保持するトークンは 403 を返す（Must-05 と共通確認）
- Must-04: `curl -s http://localhost:8080/hypotheses` (ヘッダなし) が HTTP 401、`Content-Type: application/problem+json`、`"errorCode":"AUTH_INVALID_CREDENTIALS"` を返す
- Must-05: `curl -s -H "Authorization: Bearer <jwt_without_hypotheses_read>" http://localhost:8080/hypotheses` が HTTP 403、`"errorCode":"AUTH_FORBIDDEN"` を返す
- Must-06: `curl -s -H "Authorization: Bearer <valid_jwt_hypotheses_read>" http://localhost:8080/hypotheses/01NOTEXIST00000000000000000` が HTTP 404、`"errorCode":"RESOURCE_NOT_FOUND"` を返す
- Must-07: Firestore エミュレータを停止した状態で `GET /hypotheses` を呼ぶと HTTP 503、`"errorCode":"DEPENDENCY_UNAVAILABLE"` を返す（またはハンドラ単体テストで Firestore エラーパスを assert する）
- Must-08: `curl -s -H "Authorization: Bearer <valid>" "http://localhost:8080/hypotheses"` の `items` 配列長が 30 以下; `curl ... "http://localhost:8080/hypotheses?limit=10"` の `items` 長が 10 以下
- Must-09: `curl -s -H "Authorization: Bearer <valid>" "http://localhost:8080/hypotheses?limit=201"` が HTTP 400、`"errorCode":"VALIDATION_ERROR"` を返す; `limit=0` も同様に 400 を返す
- Must-10: Must-01 レスポンスの `items[0]` に `identifier`・`symbol`・`instrumentType`・`status`・`title`・`updatedAt` が全て存在する（`jq 'del(.items[0] | .identifier,.symbol,.instrumentType,.status,.title,.updatedAt) | .items[0] == {}'` が `true` と等価の判定）
- Must-11: Must-02 レスポンス JSON に `sourceEvidence`・`skillVersion`・`instructionProfileVersion` キーが存在する（`jq 'has("sourceEvidence") and has("skillVersion") and has("instructionProfileVersion")'` が `true`）
- Must-12: `curl -s -H "Authorization: Bearer <valid>" "http://localhost:8080/hypotheses?status=invalid_value"` が HTTP 400 を返す; `status=draft` は 200 (または空 items) を返す
- Must-13: `grep -r "HypothesesHandler\|hypothesesHandler\|HypothesesAPI\|hypothesesApi\|getHypotheses\|HypothesesAPI" backend/bff/src/Main.hs backend/bff/src/Presentation/Api.hs` がいずれかのファイルでマッチを返す（結線確認）
- Must-14: `cd backend && cabal build all 2>&1 | grep -c "error:"` が 0; `hlint backend/bff/ 2>&1 | grep -cE "Warning|Error"` が 0

## Non-goals (今回やらない)

- `status` による Firestore サーバーサイドフィルタの完全実装（MVP では受付のみ）
- カーソルページネーションの完全実装（MVP では `nextCursor: null` 固定）
- `hypothesis_registry` 書き込み・更新・削除エンドポイント（参照のみ）
- 仮説昇格 (`promotionMode: auto`) のトリガーロジック（別 Issue 対象）
- Firestore 複合インデックス `(status ASC, updatedAt DESC)` の Terraform 定義（インフラ層は別 Issue）
- MNPI フィルタリングロジックの変更

## Risk

- level: high-risk
- escalate_to_opus: true
- 理由: `auth`（JWT パーミッションチェック `hypotheses:read`）・`routing`（`BffAPI` 型への `HypothesesAPI` 追加 + `bffServer` への結線）・`DI`（`FirestoreHypothesisRepository` の `AppEnv` 経由注入）の 3 境界に同時に触れる。既存の `Presentation.Handler.Insights` パターンを厳守することで変更面は限定されるが、`Presentation.Api` の型変更は公開 API 境界の変更であり reviewer/verifier 昇格が必要。

## Open questions (あれば)

- `status` クエリパラメータの型バリデーション失敗時のエラーコードを `VALIDATION_ERROR` とするか `REQUEST_VALIDATION_FAILED` とするか未確定。既存の Insights ハンドラは `limit` 範囲外を `REQUEST_VALIDATION_FAILED` で返しているが、Issue summary では `VALIDATION_ERROR` と記載されている。実装者はどちらかに統一し、本 spec の Must-09 および Must-12 の errorCode を合わせること。
- `cursor` の具体的なエンコード方式（Firestore `startAfter` ドキュメント参照、あるいは `updatedAt` 値の Base64 等）が未定義。MVP で `nextCursor: null` 固定とする場合は本 open question を閉じてよい。
