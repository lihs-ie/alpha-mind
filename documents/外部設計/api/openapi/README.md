# OpenAPI分割フォーマット

このディレクトリは、`openapi.yaml` を責務単位で分割管理するためのフォーマットです。

## 責務

- `../openapi.yaml`
  - OpenAPIドキュメントのルート。
  - `info` / `servers` / `security` / `tags` / `paths` / `components` の参照定義を持つ。
- `paths/`
  - エンドポイントごとの Path Item Object を配置する。
  - 1ファイル1パスを原則とし、`paths/index.yaml` で集約する。
- `components/schemas/`
  - 再利用する Schema Object を配置する。
- `components/responses/`
  - 共通レスポンス定義を配置する。
- `components/parameters/`
  - 共通パラメータ定義を配置する。
- `components/requestBodies/`
  - 共通リクエストボディ定義を配置する。
- `components/securitySchemes/`
  - 認証方式定義を配置する。

## 運用ルール

- 集約ファイルは各ディレクトリの `index.yaml` を正本とする。
- 実体定義は `_template.yaml` を複製して作成する。
- 参照関係は相対パス `$ref` を利用する。
- 識別子命名は `Id` を使わず `Identifier` を採用する。
- 関心ごと自身の識別子は `identifier`、他関心ごとの識別子は `{entity}` を使う（例: `user`）。
