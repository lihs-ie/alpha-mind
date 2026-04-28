# Web API統合テスト設計ベストプラクティス

最終更新日: 2026-03-05

## 1. 目的

- 本書は、サービス別API統合テスト設計書を作成する際の共通ベストプラクティスを定義する。
- 対象はHTTP APIの統合テスト（サービス内部のUnitテストは対象外）。

## 2. 適用方針（要点）

| No | ベストプラクティス | 設計書への反映ポイント | 根拠 |
|---|---|---|---|
| 1 | API契約（OpenAPI）を単一の正として扱う | OpenAPI `operationId` 単位でテスト対象一覧を作る | OpenAPI |
| 2 | HTTPメソッドの安全性/冪等性を検証する | `GET/PUT/DELETE` の再送時挙動と副作用を明記する | RFC 9110 |
| 3 | エラー応答形式を標準化する | 4xx/5xxで `application/problem+json` の検証を行う | RFC 9457 |
| 4 | 認証・認可はオブジェクト単位まで検証する | API1/API2/API3/API5観点で権限マトリクスを作る | OWASP API Security Top 10 (2023) |
| 5 | リソース消費制御を検証する | レート制限、ページサイズ上限、タイムアウトのテストを含める | OWASP API4:2023 |
| 6 | 契約テストはCIで常時実行する | Provider検証をCI必須ゲートにする | Pact Docs |
| 7 | Provider検証時はスタブ境界を厳密にする | リクエスト検証後の下位層のみスタブする | Pact Docs |
| 8 | 統合テスト環境は再現可能にする | ローカル依存を避け、使い捨てコンテナで依存を起動する | Testcontainers |
| 9 | CIではジョブ単位で依存サービスを分離する | Service Containerをジョブごとに作成/破棄する | GitHub Actions Docs |
| 10 | 分散トレース伝播を検証する | `traceparent/tracestate` とHTTP span属性を検証する | W3C Trace Context / OpenTelemetry |

## 3. サービス別設計書に必須の章

1. テスト対象API一覧（OpenAPIと対応）
2. 依存関係とテスト境界（何を実体接続し、何をスタブするか）
3. テストデータ戦略（投入/隔離/クリーンアップ）
4. エンドポイント別観点マトリクス（正常/異常/競合/認可/観測性）
5. 非機能観点（性能、耐障害、リソース制御）
6. CI実行条件とゲート（契約テスト含む）
7. トレーサビリティ（要件・リスク・テストケース対応）

## 4. 参考（一次情報）

- OpenAPI Specification: https://spec.openapis.org/oas/latest.html
- RFC 9110 (HTTP Semantics): https://www.rfc-editor.org/rfc/rfc9110.html
- RFC 9457 (Problem Details for HTTP APIs): https://www.rfc-editor.org/rfc/rfc9457
- OWASP API Security Top 10 (2023): https://owasp.org/API-Security/editions/2023/en/0x11-t10/
- OWASP API4:2023 Unrestricted Resource Consumption: https://owasp.org/API-Security/editions/2023/en/0xa4-unrestricted-resource-consumption/
- Pact Docs - Verifying Pacts: https://docs.pact.io/provider
- Pact Docs - When to use Pact: https://docs.pact.io/getting_started/what_is_pact_good_for
- Testcontainers JUnit5 Quickstart: https://java.testcontainers.org/quickstart/junit_5_quickstart/
- GitHub Actions - Service Containers: https://docs.github.com/en/actions/tutorials/use-containerized-services/use-docker-service-containers
- W3C Trace Context: https://www.w3.org/TR/trace-context/
- OpenTelemetry HTTP Spans: https://opentelemetry.io/docs/specs/semconv/http/http-spans/
