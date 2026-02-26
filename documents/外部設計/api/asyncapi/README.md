# AsyncAPI分割フォーマット

このディレクトリは、`asyncapi.yaml` を責務単位で分割管理するためのフォーマットです。

## 責務

- `../asyncapi.yaml`
  - AsyncAPIドキュメントのルート。
  - `info` / `servers` / `channels` / `operations` / `components` の参照定義を持つ。
- `channels/`
  - トピック（channel）定義を管理する。
- `operations/`
  - publish/subscribe 操作定義を管理する。
- `components/messages/`
  - メッセージ定義を管理する。
- `components/schemas/`
  - payloadや共通データのスキーマ定義を管理する。
- `components/securitySchemes/`
  - 認証方式定義を管理する。

## 運用ルール

- 集約ファイルは各ディレクトリの `index.yaml` を正本とする。
- 実体定義は `_template.yaml` を複製して作成する。
- 参照関係は相対パス `$ref` を利用する。
- 識別子命名は `Id` を使わず `Identifier` を採用する。
- 関心ごと自身の識別子は `identifier`、他関心ごとの識別子は `{entity}` を使う（例: `user`）。
