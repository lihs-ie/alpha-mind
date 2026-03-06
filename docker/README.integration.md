# Integration Compose Configs

サービス別統合テスト向けの compose 構成。

## 方針

- 共通依存（Firestore / PubSub / GCS / init）は `docker/docker-compose.integration.base.yml` に集約。
- サービスごとの差分は `docker/docker-compose.integration.<service>.yml` に分離。
- CI用の BuildKit キャッシュ設定は `docker/docker-compose.integration.cache.yml` に分離。
- Haskell サービス向けの GHCR レジストリキャッシュ差分は `docker/docker-compose.integration.cache.registry.yml` に分離。
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
- CIマトリクスは `max-parallel: 6` で実行し、並列性と安定性を両立する。
- CIでは `build --builder <buildx> + up --no-build` を使い、Haskell/Python イメージの再ビルドを最小化する。
- CIでは対象サービスのみを `build/up` し、不要サービスのビルドを避ける。
- CIでは Haskell サービスに対して `type=gha` と `type=registry(GHCR)` を併用し、キャッシュヒット率を安定化する。
- fork 由来の PR ではレジストリ書き込み権限がないため、GHCR キャッシュ書き込みを自動で無効化し `type=gha` のみ利用する。
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
