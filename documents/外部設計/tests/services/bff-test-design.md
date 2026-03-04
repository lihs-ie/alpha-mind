# bff テスト設計書

最終更新日: 2026-03-03  
文書バージョン: v0.1  
対象サービス: bff

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 作成者 | Codex |
| 関連要件 | `documents/機能仕様書.md` |
| 関連設計 | `documents/外部設計/services/bff.md`, `documents/外部設計/api/openapi.yaml` |
| 適用リリース | `2026.03`（Tag運用: `stg-{yyyyMMddHHmm}` -> `prod-{yyyyMMddHHmm}`） |

## 2. 目的と適用範囲

- BFF公開APIの契約整合、認証認可、監査記録、下流委譲を検証する。
- 対象は主要同期API、イベント発行、JWT認証。

## 3. テスト方針

- OpenAPI契約テストを中心に正常/異常/競合（409）を網羅する。
- 更新系APIは `trace` 採番と監査記録を必須確認する。
- `orders approve/reject` は risk-guard内部API委譲結果まで結合確認する。

## 4. テスト対象と品質リスク

| リスクID | リスク内容 | 影響度 | 発生確率 | 対応 |
|---|---|---:|---:|---|
| BFF-RSK-01 | 認証回避 | 5 | 2 | JWT必須/期限切れ/改ざんテスト |
| BFF-RSK-02 | API契約不整合 | 4 | 3 | スキーマ検証 |
| BFF-RSK-03 | 下流障害時の誤応答 | 4 | 3 | 503/409ハンドリング検証 |

## 5. テストレベル・タイプ・技法

| 観点 | 内容 |
|---|---|
| レベル | Unit / Integration / System |
| タイプ | 機能、認証認可、異常系、回帰 |
| 技法 | 同値分割、境界値分析、デシジョンテーブル |

## 6. エントリ/イグジット基準

- エントリ: OpenAPI確定、JWT鍵設定、下流モック準備済み。
- イグジット: 実行率100%、重大欠陥0件、参照API p95 < 500ms。

## 7. テスト環境・データ・ツール

| 区分 | 内容 |
|---|---|
| 環境 | `local`, `stg` |
| テストデータ | 正常系・異常系の固定データセット |
| ツール | `cabal build` / `cabal test`, `pnpm --package=@redocly/cli dlx redocly lint documents/外部設計/api/openapi.yaml`, Cloud Logging, Cloud Monitoring |

## 8. 要件トレーサビリティ

| UC ID | テスト条件ID | テストケースID |
|---|---|---|
| UC-API-01 | BFF-COND-01 run-cycle受付 | BFF-TC-001 |
| UC-API-02 | BFF-COND-02 kill-switch変更 | BFF-TC-002 |

## 9. 主要テストケース

| テストケースID | 観点 | 期待結果 |
|---|---|---|
| BFF-TC-001 | `POST /commands/run-cycle` | `market.collect.requested`発行、200応答 |
| BFF-TC-002 | `POST /operations/kill-switch` | 状態保存と `operation.kill_switch.changed` 発行 |
| BFF-TC-003 | JWT欠落/期限切れ | 401/403応答 |
| BFF-TC-004 | `POST /orders/{identifier}/approve` | risk-guard内部APIへ委譲し結果を返却 |
| BFF-TC-005 | 下流障害 | 503応答、監査ログ記録 |

## 10. 欠陥管理

- Critical: 認証バイパス、更新系API誤実行。
- High: 契約不整合、監査未記録。

## 11. 品質メトリクス

| 指標 | 目標 |
|---|---|
| 契約テスト成功率 | 100% |
| 更新系監査記録率 | 100% |
| 参照API応答 | p95 < 500ms |

## 12. 体制・役割・スケジュール

| 項目 | 内容 |
|---|---|
| 体制 | 開発 + QA + PO |
| 進め方 | 設計レビュー後に実行、完了判定会で終了判断 |
| スケジュール | 毎週火曜: 設計レビュー -> 毎週水曜〜木曜: STG実行 -> 毎週金曜: 完了判定（必要時は翌営業日にPROD昇格判定） |

## 13. 変更履歴

| 日付 | 版 | 変更内容 |
|---|---|---|
| 2026-03-03 | v0.1 | 初版作成 |

## 14. 参考

- `documents/外部設計/テスト設計書テンプレート.md`
