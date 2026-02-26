# Terraform監視設定設計（Step 8）

最終更新日: 2026-02-24

## 1. 目的

- `外部設計/operations/監視クエリ設計.md` を、Terraformで再現可能な監視設定として設計する。
- 手動設定を排除し、SLO/アラート/通知チャネルをコードで一元管理する。

## 2. 調査結果サマリ（設計方法）

1. 運用フローは `plan -> 承認 -> apply` を必須化する。  
2. Terraform実行は手作業ではなくCI/CDで自動化する。  
3. Stateはリモート（GCS backend）で管理し、ロック・バージョニングを有効化する。  
4. Stateの手編集は禁止し、必要時のみ `terraform state` 系コマンドを使用する。  
5. Root moduleは肥大化させず、監視領域を独立したroot/moduleに分割する。  
6. Cloud MonitoringはTerraformで `google_monitoring_alert_policy` と `google_monitoring_notification_channel` を管理できる。  
7. SLO APIは `services` と `serviceLevelObjectives` を持ち、IaC化対象は「サービス定義 + SLO定義 + Burn Rate Alert + 補助モニタAlert」の4層で設計する。  

## 3. 採用アーキテクチャ

## 3.1 ディレクトリ構成（推奨）

```text
infra/monitoring/
  versions.tf
  providers.tf
  backend.hcl
  envs/
    prod/
      main.tf
      variables.tf
      outputs.tf
      terraform.tfvars
  modules/
    notification-channels/
      main.tf
      variables.tf
      outputs.tf
    custom-services/
      main.tf
      variables.tf
      outputs.tf
    slos/
      main.tf
      variables.tf
      outputs.tf
    burn-rate-alerts/
      main.tf
      variables.tf
      outputs.tf
    supplemental-monitor-alerts/
      main.tf
      variables.tf
      outputs.tf
  generated/
    slo-catalog.json
    slo-query-spec.json
```

## 3.2 設計意図

- root moduleを監視専用に分離し、他インフラ変更と独立してレビュー/適用できるようにする。
- module単位で責務を分離し、通知・SLO・アラートを個別に差分管理できるようにする。
- `generated/` に正本JSON（既存の外部設計成果物）を配置し、`jsondecode(file(...))` で読み込む。

## 4. Terraformリソース設計

## 4.1 通知チャネル層

- 役割: 障害通知先（email等）を定義。
- 主な管理対象:
  - `google_monitoring_notification_channel`

## 4.2 監視サービス/SLO層

- 役割: 監視対象サービスとSLOを定義。
- 主な管理対象:
  - `google_monitoring_custom_service`
  - `google_monitoring_slo`

注記:
- `google_monitoring_custom_service` は、Cloud Monitoringの `Service`（custom service）に対応。
- `google_monitoring_slo` は、Cloud Monitoringの `serviceLevelObjectives` に対応。

## 4.3 Burn Rate Alert層

- 役割: `14.4 / 6 / 1` の3段階Burn Rate通知を定義。
- 主な管理対象:
  - `google_monitoring_alert_policy`
- 通知先:
  - `notification_channel_names` で `page` / `ticket` を分離。

## 4.4 補助モニタAlert層

- 役割: `supplementalMonitors`（`MON-001`〜`MON-004`）の閾値監視を定義。
- 主な管理対象:
  - `google_monitoring_alert_policy`
- 通知先:
  - 重要度に応じて `page` / `ticket` を使い分ける。

## 5. SLO定義連携（既存成果物との接続）

## 5.1 入力ファイル

- `外部設計/operations/slo-catalog.json`
- `外部設計/operations/slo-query-spec.json`

## 5.2 変換方針

1. `slo-catalog.json` から `id`, `objective`, `service` を読み込む。  
2. `slo-query-spec.json` から `numerator`, `denominator`, `burnRatePolicies`, `supplementalMonitors` を読み込む。  
3. Terraform local値でmap化し、`for_each` で `google_monitoring_slo` と `google_monitoring_alert_policy` を生成する。  
4. `supplementalMonitors` はSLO APIではなくAlert Policyとして実装する。  

## 6. 権限/IAM設計

- 最小要件（公式ドキュメント準拠）:
  - `roles/monitoring.editor`（SLO/Alert作成）
  - `roles/monitoring.notificationChannelEditor`（通知チャネル作成）
- 追加要件:
  - ログベースアラートを使う場合 `roles/logging.configWriter`

## 7. State管理設計

## 7.1 backend

- `gcs` backend を採用。
- 設計ルール:
  - 専用bucketを使用
  - Object Versioning有効化
  - State Lockingを有効利用（`-lock=false` を常用しない）

## 7.2 State運用禁止事項

- `terraform.tfstate` の手編集禁止
- `terraform state push -force` の常用禁止

## 8. CI/CD運用設計

## 8.1 必須パイプライン

1. `terraform fmt -check`
2. `terraform init`
3. `terraform validate`
4. `terraform plan -out=tfplan`
5. 人手レビュー（plan差分）
6. `terraform apply tfplan`

## 8.2 既存手動設定の取り込み

- 既存アラートをTerraform化する場合:
  - `import` block を使用
  - `terraform plan -generate-config-out=generated.tf` を使って定義を生成

## 9. 運用ルール

- 監視設定変更はPull Request必須
- 本番の `apply` は保存済みplanのみ許可
- 週次でdrift確認（`terraform plan`）
- Error Budget 50%以上時は監視設定のノイズ削減・優先度見直しを実施

## 10. 受入基準（Step 8）

1. 通知チャネル、SLO、Burn Rateアラート、補助モニタAlertがすべてTerraform管理対象になっている。  
2. `slo-catalog.json` / `slo-query-spec.json` からの自動展開方針が定義されている。  
3. backend, IAM, CI/CD, import手順が設計書に明記されている。  
4. 監視設定が手動変更されても再適用で収束できる運用になっている。  

## 11. 根拠ソース

- Create alerting policies with Terraform  
  https://docs.cloud.google.com/monitoring/alerts/terraform
- Create and manage notification channels with Terraform  
  https://cloud.google.com/monitoring/alerts/notification-terraform
- Manage alerting policies with Terraform（import / generate-config-out）  
  https://docs.cloud.google.com/monitoring/alerts/manage-alerts-terraform
- SLO API（services / serviceLevelObjectives）  
  https://docs.cloud.google.com/stackdriver/docs/solutions/slo-monitoring/api/using-api
- REST Resource: services.serviceLevelObjectives  
  https://docs.cloud.google.com/monitoring/api/ref_v3/rest/v3/services.serviceLevelObjectives
- Terraform best practices for operations（plan first / pipeline / state手編集禁止）  
  https://cloud.google.com/docs/terraform/best-practices/operations
- Terraform best practices for root modules（root module肥大化抑制）  
  https://cloud.google.com/docs/terraform/best-practices/root-modules
- Terraform best practices for general style and structure  
  https://cloud.google.com/docs/terraform/best-practices/general-style-structure
- Terraform security best practices（remote state推奨）  
  https://cloud.google.com/docs/terraform/best-practices/security
- Terraform gcs backend（state locking / object versioning推奨）  
  https://developer.hashicorp.com/terraform/language/backend/gcs
- Terraform state locking  
  https://developer.hashicorp.com/terraform/language/state/locking
- terraform validate command  
  https://developer.hashicorp.com/terraform/cli/commands/validate
- terraform plan command  
  https://developer.hashicorp.com/terraform/cli/commands/plan
- terraform apply command  
  https://developer.hashicorp.com/terraform/cli/commands/apply
- Cloud Monitoring service discovery changes（`google_monitoring_custom_service` 記載）  
  https://cloud.google.com/blog/products/management-tools/changes-to-cloud-monitoring-service-discovery/
- terraform-google-slo（`google_monitoring_slo` 利用例）  
  https://github.com/terraform-google-modules/terraform-google-slo
