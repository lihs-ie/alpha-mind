# insight-collector テスト設計書

最終更新日: 2026-03-03  
文書バージョン: v0.2  
対象サービス: insight-collector

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 作成者 | Codex |
| 関連要件 | `documents/機能仕様書.md` |
| 関連設計 | `documents/外部設計/services/insight-collector.md` |
| 適用リリース | `2026.03`（Tag運用: `stg-{yyyyMMddHHmm}` -> `prod-{yyyyMMddHHmm}`） |

## 2. 目的と適用範囲

- 定性データ収集処理の正確性とコンプライアンス遮断を検証する。
- 対象は `insight.collect.requested` 受信から収集・保存・結果イベント発行まで。

## 3. テスト方針

- 許可リスト/利用規約違反遮断を最優先で検証する。
- 収集成功時の根拠情報（`sourceUrl`, `collectedAt`, `evidenceSnippet`）保持を必須確認する。
- 失敗時は理由コード付き `insight.collect.failed` を確認する。

## 4. テスト対象と品質リスク

| リスクID | リスク内容 | 影響度 | 発生確率 | 対応 |
|---|---|---:|---:|---|
| IC-RSK-01 | 規約違反ソース収集 | 5 | 2 | ポリシー遮断テスト |
| IC-RSK-02 | 根拠情報欠落 | 4 | 3 | 出力必須項目検証 |
| IC-RSK-03 | 失敗理由コード不整合 | 3 | 3 | 異常系イベント検証 |
| IC-RSK-04 | sourceConfigキー不足（x/youtube/paper/github） | 4 | 2 | ポリシー設定バリデーション |
| IC-RSK-05 | sourceStatus欠落で部分失敗を見逃す | 4 | 2 | 成功イベント契約テスト |
| IC-RSK-06 | `signalClass` 未設定で下流判定不能 | 4 | 2 | 出力必須項目検証 |
| IC-RSK-07 | `soWhatScore` 範囲外値の混入 | 4 | 2 | 境界値テスト |

## 5. テストレベル・タイプ・技法

| 観点 | 内容 |
|---|---|
| レベル | Unit / Integration / System |
| タイプ | 機能、セキュリティ/コンプライアンス、異常系 |
| 技法 | 同値分割、デシジョンテーブル |

## 6. エントリ/イグジット基準

- エントリ: source_policies、API資格情報、Storage/Firestoreが準備済み。
- エントリ: `sourcePolicies[].sourceConfig.x.accountHandles` / `sourcePolicies[].sourceConfig.youtube.channelIdentifiers` / `sourcePolicies[].sourceConfig.paper.providers` / `sourcePolicies[].sourceConfig.github.repositories` が設定済み。
- イグジット: 実行率100%、重大欠陥0件、1サイクル20分以内。

## 7. テスト環境・データ・ツール

| 区分 | 内容 |
|---|---|
| 環境 | `local`, `stg` |
| テストデータ | 正常系・異常系の固定データセット |
| ツール | `cabal build` / `cabal test`, Cloud Logging, Cloud Monitoring |

## 8. 要件トレーサビリティ

| UC ID | テスト条件ID | テストケースID |
|---|---|---|
| UC-IC-01 | IC-COND-01 定時収集成功 | IC-TC-001 |
| UC-IC-02 | IC-COND-02 不許可ソース遮断 | IC-TC-002 |
| UC-IC-03 | IC-COND-03 規約違反遮断 | IC-TC-003 |

## 9. 主要テストケース

| テストケースID | 観点 | 期待結果 |
|---|---|---|
| IC-TC-001 | 許可済みソース収集 | インサイト保存、`insight.collected`発行 |
| IC-TC-002 | 許可外ソース指定 | `insight.collect.failed`発行（理由コード付き） |
| IC-TC-003 | 規約条件未充足 | `COMPLIANCE_SOURCE_UNAPPROVED`で失敗 |
| IC-TC-004 | 収集成功データ | 根拠3項目が全件保持される |
| IC-TC-005 | `sourceConfig` 必須キー欠落 | `REQUEST_VALIDATION_FAILED` で失敗 |
| IC-TC-006 | `sourceTypes` 指定実行 | 指定ソースのみ収集対象になる |
| IC-TC-007 | `insight.collected.payload.sourceStatus` | ソース別 `status/collectedCount` が保持される |
| IC-TC-008 | `insight.collect.failed.payload.stage` | `sourceType/stage` が復旧判断可能な値で出力される |
| IC-TC-009 | `soWhatScore=0.70` | `signalClass=structural_anomaly` に分類される |
| IC-TC-010 | `soWhatScore=0.6999` | `signalClass=event_noise` に分類される |
| IC-TC-011 | `soWhatScore<0` または `>1` | `DATA_SCHEMA_INVALID` で失敗 |
| IC-TC-012 | `signalClass` 欠損 | `insight.collect.failed` 発行、成功保存されない |

## 10. 欠陥管理

- Critical: 規約違反収集の通過。
- High: 根拠情報欠落、誤理由コード。

## 11. 品質メトリクス

| 指標 | 目標 |
|---|---|
| コンプライアンス遮断成功率 | 100% |
| 根拠情報充足率 | 100% |
| サイクル完了時間 | 20分以内 |

## 12. 体制・役割・スケジュール

| 項目 | 内容 |
|---|---|
| 体制 | 開発 + QA + PO |
| 進め方 | 設計レビュー後に実行、完了判定会で終了判断 |
| スケジュール | 毎週火曜: 設計レビュー -> 毎週水曜〜木曜: STG実行 -> 毎週金曜: 完了判定（必要時は翌営業日にPROD昇格判定） |

## 13. 変更履歴

| 日付 | 版 | 変更内容 |
|---|---|---|
| 2026-03-03 | v0.2 | `signalClass` / `soWhatScore` の境界値・異常系ケースを追加 |
| 2026-03-03 | v0.1 | 初版作成 |

## 14. 参考

- `documents/外部設計/テスト設計書テンプレート.md`
