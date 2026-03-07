# Python共通モジュール設計

最終更新日: 2026-03-07

## 1. 目的

- `feature-engineering` と `signal-generator` に重複している Python 実装を洗い出し、共通モジュールとして切り出せる対象を定義する。
- 今後 Python 実装が追加される `hypothesis-lab` でも再利用できるディレクトリ設計を先に決める。
- ドメイン固有ロジックまで共通化せず、Cloud Run 上のイベント駆動サービスに共通する基盤処理に限定する。

## 2. 対象サービスの現状

| サービス | 実装状況 | 主な共通化対象 |
|---|---|---|
| `feature-engineering` | Pub/Sub push 受信、Firestore、Cloud Storage、Pub/Sub publish まで実装済み | CloudEvent デコード、GCP クライアント初期化、冪等性、イベント publish、構造化ログ |
| `signal-generator` | Pub/Sub push 受信、Firestore、Cloud Storage、Pub/Sub publish、再試行まで実装済み | CloudEvent デコード、GCP クライアント初期化、冪等性、イベント publish、Storage ユーティリティ、再試行 |
| `hypothesis-lab` | `/healthz` のみ実装 | 今回は具体的な共通処理は未抽出。将来利用する受け皿のみ定義する |

## 3. 共通モジュールとして定義可能なもの

### 3.1 CloudEvents / Pub/Sub push デコード

現状の実装:

- `backend/feature-engineering/src/presentation/cloud_event_decoder.py`
- `backend/signal-generator/src/signal_generator/presentation/cloud_event_decoder.py`

共通化できる理由:

- Pub/Sub push の `message.data` Base64 デコード
- CloudEvents エンベロープの共通項目検証 (`identifier`, `eventType`, `occurredAt`, `trace`, `schemaVersion`, `payload`)
- ULID / ISO8601 UTC バリデーション
- 失敗時の例外モデル

共通モジュール化する範囲:

- Push body から CloudEvents JSON を取り出す処理
- エンベロープ共通バリデータ
- `identifier` / `trace` の best-effort 抽出
- payload の個別デコードは各サービスに残す

補足:

- `market.collected` と `features.generated` では payload 形状が異なるため、payload まで 1 つの関数に寄せると逆に密結合になる。
- 共通モジュールでは「エンベロープまで」を責務とし、payload の DTO 化はサービス側で行う。

### 3.2 Pub/Sub イベント発行

現状の実装:

- `backend/feature-engineering/src/infrastructure/messaging/pubsub/features_generated_publisher.py`
- `backend/feature-engineering/src/infrastructure/messaging/pubsub/features_generation_failed_publisher.py`
- `backend/feature-engineering/src/infrastructure/event_mapping/domain_to_integration_event_mapper.py`
- `backend/signal-generator/src/signal_generator/infrastructure/messaging/pubsub_signal_event_publisher.py`

共通化できる理由:

- CloudEvents エンベロープの共通属性組み立て
- `PublisherClient` を使った publish と message ID 取得
- CloudEvents attribute を Pub/Sub attributes に載せる責務
- topic path 解決

共通モジュール化する範囲:

- CloudEvents publisher の土台クラス
- `project_id` と topic 名から topic path を作るユーティリティ
- 共通エンベロープ属性 (`identifier`, `trace`, `occurredAt`, `schemaVersion`) の検証

サービス側に残す範囲:

- eventType ごとの payload マッピング
- topic 名の定義
- domain event から integration event への変換

### 3.3 Firestore ベースの冪等性リポジトリ

現状の実装:

- `backend/feature-engineering/src/infrastructure/persistence/firestore/firestore_idempotency_key_repository.py`
- `backend/signal-generator/src/signal_generator/infrastructure/firestore/firestore_idempotency_key_repository.py`

共通化できる理由:

- 保存先コレクションはどちらも `idempotency_keys`
- TTL 30 日、`identifier` / `service` / `trace` / `processedAt` / `expiresAt` / `updatedAt` の考え方は同系統
- サービス名プレフィックス付きキーの方針は `documents/内部設計/共通設計.md` と一致している

設計上の注意:

- `feature-engineering` は `reserve / release / persist / terminate` を持つリース方式
- `signal-generator` は `find / persist / terminate` の簡易方式

結論:

- 共通モジュールでは `LeaseBasedFirestoreIdempotencyRepository` を標準実装として定義する。
- `signal-generator` は将来的にこの標準実装へ寄せる。
- 現時点では API 差分があるため、一括置換ではなく段階移行にする。

### 3.4 Cloud Storage ユーティリティ

現状の実装:

- `backend/feature-engineering/src/infrastructure/persistence/cloud_storage/cloud_storage_market_data_repository.py`
- `backend/feature-engineering/src/infrastructure/persistence/cloud_storage/cloud_storage_feature_artifact_repository.py`
- `backend/signal-generator/src/signal_generator/infrastructure/storage/cloud_storage_feature_reader.py`
- `backend/signal-generator/src/signal_generator/infrastructure/storage/cloud_storage_signal_writer.py`
- `backend/signal-generator/src/signal_generator/infrastructure/storage/gs_uri_parser.py`

共通化できる理由:

- `gs://` URI の解釈
- JSON メタデータの read/write
- Blob 読み書きと例外ラップ
- Parquet バイト列の upload / download の補助

共通モジュール化する範囲:

- `gs://` URI parser
- JSON metadata reader / writer
- Cloud Storage I/O helper
- Parquet file reader / writer helper

サービス側に残す範囲:

- `FeatureArtifact` や `MarketSnapshot` への変換
- バケット名やオブジェクトパスの業務ルール

### 3.5 GCP クライアント初期化と設定ロード

現状の実装:

- `backend/feature-engineering/src/presentation/dependency_container.py`
- `backend/signal-generator/src/signal_generator/presentation/dependency_container.py`

共通化できる理由:

- 環境変数の必須チェック
- Firestore / Storage / Pub/Sub client の初期化
- サービス起動時の bootstrap

共通モジュール化する範囲:

- required env loader
- typed settings
- Firestore / Storage / Pub/Sub client factory

サービス側に残す範囲:

- usecase や repository の配線
- MLflow などサービス固有の外部依存

### 3.6 再試行ポリシー

現状の実装:

- `backend/signal-generator/src/signal_generator/infrastructure/retry.py`

共通化できる理由:

- `documents/内部設計/共通設計.md` の「指数バックオフで最大3回再試行」と一致
- Cloud Storage / Pub/Sub / Firestore の一時障害対策として他サービスでも再利用しやすい

結論:

- `with_retry` は最小単位で先に共通化してよい。
- retry 対象例外の集合は共通モジュール側で一元管理する。

### 3.7 構造化ログ / 監査ログコンテキスト

現状の実装:

- `backend/feature-engineering/src/presentation/subscriber.py`
- `backend/feature-engineering/src/presentation/logging_audit_writer.py`
- `backend/signal-generator/src/signal_generator/presentation/subscriber.py`

共通化できる理由:

- `service`, `identifier`, `trace`, `eventType`, `reasonCode` を `extra` に載せる方針が共通
- decode 失敗 / duplicate / retryable failure のログ出力点が類似

共通モジュール化する範囲:

- structured log context builder
- 監査ログ出力の基底ヘルパー

サービス側に残す範囲:

- 監査イベント名
- 業務固有の追加フィールド

## 4. 今回は共通化対象にしないもの

- Domain model / Value Object / ReasonCode enum
- `feature-engineering` の特徴量生成ルール
- `signal-generator` のモデル選定、MLflow 連携、推論ロジック
- `hypothesis-lab` の将来のバックテスト業務ロジック

理由:

- これらは名前が似ていても業務意味が異なる。
- 先に共通基盤を切り出し、業務ロジックの共通化は必要性が確認できてから判断する。

## 5. 推奨ディレクトリ設計

### 5.1 追加するトップレベル

`backend/common/python` を新設し、Python サービス専用の共通パッケージを置く。

```text
backend/
  common/
    python/
      pyproject.toml
      src/
        alpha_mind_backend_common/
          __init__.py
          runtime/
            __init__.py
            env.py
            settings.py
            gcp_clients.py
          messaging/
            __init__.py
            cloud_events.py
            pubsub_push.py
            pubsub_publisher.py
          firestore/
            __init__.py
            idempotency.py
          storage/
            __init__.py
            gs_uri.py
            json_metadata.py
            parquet_io.py
          resilience/
            __init__.py
            retry.py
          observability/
            __init__.py
            logging.py
      tests/
        ...
```

### 5.2 各サービス側の配置方針

サービス固有コードは現行の `src` 配下に残し、共通基盤のみ `alpha_mind_backend_common` を import する。

例:

```text
backend/feature-engineering/src/
  presentation/
    cloud_event_decoder.py        # payload デコードのみ担当
    dependency_container.py       # サービス固有の配線のみ担当
  infrastructure/
    messaging/
      features_generated_publisher.py

backend/signal-generator/src/signal_generator/
  presentation/
    cloud_event_decoder.py        # payload デコードのみ担当
    dependency_container.py       # サービス固有の配線のみ担当
  infrastructure/
    messaging/
      pubsub_signal_event_publisher.py
```

### 5.3 import 境界

- `alpha_mind_backend_common` は domain 層を import しない
- 共通モジュールは GCP SDK と標準ライブラリ中心に留める
- サービス側が共通モジュールを利用する一方向依存にする

これにより、共通モジュールが特定サービスの domain model に引っ張られることを防ぐ。

## 6. パッケージ管理方針

現状:

- `feature-engineering` は `pyproject.toml` を持つが build-system 定義がない
- `signal-generator` は setuptools ベースでパッケージ化されている
- `hypothesis-lab` は `requirements.txt` のみ

方針:

- まず `backend/common/python` を独立した Python パッケージとして作る
- 各サービスはローカル依存としてこのパッケージを参照する
- その後、Python サービスの build-system と依存定義を段階的に統一する

補足:

- 共通モジュール切り出しと各サービスの packaging 統一は別タスクとして扱う
- 今回の設計では、ディレクトリだけ先に固定し、依存注入の実装は段階移行とする

## 7. 切り出し優先順位

### Phase 1: 先に切り出す

- `resilience.retry`
- `storage.gs_uri`
- `runtime.env`
- `messaging.cloud_events`

理由:

- 業務ロジック依存が薄く、既存コードへの影響も小さい

### Phase 2: API を揃えてから切り出す

- `messaging.pubsub_publisher`
- `firestore.idempotency`
- `observability.logging`
- `storage.json_metadata`

理由:

- 各サービスで責務は近いが API 差分がある

### Phase 3: Python サービス追加時に利用する

- `runtime.settings`
- `runtime.gcp_clients`
- Pub/Sub subscriber bootstrap 共通部

理由:

- `hypothesis-lab` が本格実装されるタイミングで効果が大きい

## 8. 初回リファクタリング時のルール

- 1 回の PR で domain ロジックと共通モジュール抽出を同時にやらない
- まず既存実装の振る舞いを固定するテストを先に追加する
- 共通モジュール側は payload を知らない薄い API に留める
- `feature-engineering` のリース型冪等性を標準とし、他サービスをそこへ寄せる

## 9. 結論

- Python サービス間で今すぐ共通化できるのは、イベント受信・イベント発行・GCP クライアント初期化・Cloud Storage ユーティリティ・再試行・構造化ログ・冪等性基盤である。
- 置き場所は `backend/common/python/src/alpha_mind_backend_common` を推奨する。
- 最初の抽出対象は `retry`, `gs_uri`, `env`, `CloudEvents` の 4 つとし、冪等性と publisher は API を揃えてから第2段階で切り出す。
