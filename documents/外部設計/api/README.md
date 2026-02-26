# API設計

最終更新日: 2026-02-26

## 1. OpenAPI

- 仕様書: `外部設計/api/openapi.yaml`
- 対象: BFF（`svc-bff`）の同期API

## 2. AsyncAPI

- 仕様書: `外部設計/api/asyncapi.yaml`
- 対象: マイクロサービス間イベント契約（Pub/Sub）

## 3. 方針

- 画面外部設計（`外部設計/screens/*.md`）に必要なAPIを網羅する。
- 認証はBearer JWT（`/healthz`, `/auth/login`を除く）。
- エラー形式は RFC 9457 互換（`application/problem+json`）。
- イベントは CloudEvents 互換エンベロープ（`identifier`, `eventType`, `occurredAt`, `trace`, `schemaVersion`, `payload`）を使用する。
- `reasonCode` は `外部設計/error/error-codes.json` を正本としてOpenAPI/AsyncAPIに反映する。
- 認証・認可の正本は `外部設計/security/認証認可設計.md` と `外部設計/security/authz-matrix.json` とする。
- モデル検証APIは `degradationFlag` とコスト控除指標（`costAdjustedReturn`, `slippageAdjustedSharpe`）を含む。
- `signal.generated` イベントは `modelDiagnostics` を含み、劣化判定とコンプライアンスレビュー要否を伝播する。
- 更新系APIの手動入力は `reasonCode` + `comment`（最大120文字）に制限し、MNPI疑義は拒否する。
- コンプライアンス拒否は `COMPLIANCE_*` 系 `reasonCode` で統一する。
- `GET/PUT /compliance/controls` で制限銘柄とブラックアウト期間を管理する。
- インサイト/仮説系APIを追加し、定性分析結果から仮説検証までをBFF経由で一貫操作できるようにする。
- AsyncAPIに `insight.*` と `hypothesis.*` ドメインイベントを追加し、既存イベントチェーンと疎結合に連携する。

## 4. 次の拡張

- OpenAPI examples の拡充
- AsyncAPI examples の拡充
- スキーマバージョニング運用ルール（breaking change規約）
- `run-insight-cycle` / `insights` / `hypotheses` 系エンドポイントのOpenAPI反映
- `insight.collect.requested` / `hypothesis.proposed` / `hypothesis.backtested` 系イベントのAsyncAPI反映

## 5. 分割フォーマット（新規）

- OpenAPI分割ルート: `外部設計/api/openapi.yaml`
- AsyncAPI分割ルート: `外部設計/api/asyncapi.yaml`

### OpenAPI分割責務

- `openapi.yaml`: `info` / `servers` / `security` / `tags` / `paths` / `components` のルート集約
- `openapi/paths/`: Path Item Object（1ファイル1パス）
- `openapi/components/schemas/`: 共通スキーマ
- `openapi/components/responses/`: 共通レスポンス
- `openapi/components/parameters/`: 共通パラメータ
- `openapi/components/requestBodies/`: 共通リクエストボディ
- `openapi/components/securitySchemes/`: 認証方式

### AsyncAPI分割責務

- `asyncapi.yaml`: `info` / `servers` / `channels` / `operations` / `components` のルート集約
- `asyncapi/channels/`: トピック（Channel）定義
- `asyncapi/operations/`: send/receive 操作定義
- `asyncapi/components/messages/`: Message Object
- `asyncapi/components/schemas/`: payload/共通スキーマ
- `asyncapi/components/securitySchemes/`: 認証方式

## 6. 命名規約（Identifier）

- `Id` は略記として使わない。識別子は `Identifier` として表記する。
- 関心ごとそのものの識別子は、型内で `identifier` フィールド名を使う。
- その型が保持する他関心ごとの識別子は、`{entity}Identifier` ではなく `{entity}` フィールド名を使う。
- 例: `EventPayload` の自分自身の識別子は `eventId` ではなく `identifier`。
- 例: `EventPayload` がユーザー識別子を保持する場合は `userIdentifier` ではなく `user`。
