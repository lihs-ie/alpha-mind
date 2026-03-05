# Integration Compose Profiles

サービス別統合テスト向けの compose 構成。

## 方針

- 共通依存（Firestore / PubSub / GCS / init）は `docker/docker-compose.integration.base.yml` に集約。
- サービスごとの差分は `docker/docker-compose.integration.<service>.yml` に分離。
- 実行時は `-f` で合成する。

## 使い方

`docker/` ディレクトリで実行:

```bash
make integration-up SERVICE=bff
make integration-ps SERVICE=bff
make integration-logs SERVICE=bff
make integration-down SERVICE=bff
```

## CIでの衝突回避

- `COMPOSE_PROJECT_NAME` をジョブごとに一意化する。
- CIマトリクスは `max-parallel: 1` で実行し、共有ポート競合を回避する。
- 終了処理は `always()` で `integration-down` を必ず実行する。

## 対応サービス

- `bff`
- `data-collector`
- `feature-engineering`
- `signal-generator`
- `portfolio-planner`
- `risk-guard`
- `execution`
- `audit-log`
- `insight-collector`
- `agent-orchestrator`
- `hypothesis-lab`
