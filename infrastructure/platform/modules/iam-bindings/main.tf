# iam-bindings: Assign roles to service accounts per INF-003
# Common roles applied to all runtime SAs, plus service-specific additional roles

locals {
  # Common roles assigned to all runtime service accounts (INF-003 section 6.2)
  common_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/datastore.user",
  ]

  # Service accounts that should NOT receive common runtime roles
  non_runtime_service_accounts = toset(["ops", "scheduler"])

  # Cartesian product of runtime SA emails x common roles (excluding non-runtime SAs)
  common_bindings = flatten([
    for sa_key, sa_email in var.service_account_emails : [
      for role in local.common_roles : {
        key    = "${sa_key}__${role}"
        member = "serviceAccount:${sa_email}"
        role   = role
      }
    ] if !contains(local.non_runtime_service_accounts, sa_key)
  ])

  # Service-specific additional roles (INF-003 section 6.3)
  # Each entry: { member, role, bucket (optional), service (optional) }
  additional_project_bindings = [
    # bff (run.invoker is bound at service level, not project level -- see below)
    { key = "bff__pubsub_publisher", member = "serviceAccount:${var.service_account_emails["bff"]}", role = "roles/pubsub.publisher" },
    { key = "bff__secret_accessor", member = "serviceAccount:${var.service_account_emails["bff"]}", role = "roles/secretmanager.secretAccessor" },
    # data-collector
    { key = "data-collector__pubsub_subscriber", member = "serviceAccount:${var.service_account_emails["data-collector"]}", role = "roles/pubsub.subscriber" },
    { key = "data-collector__pubsub_publisher", member = "serviceAccount:${var.service_account_emails["data-collector"]}", role = "roles/pubsub.publisher" },
    { key = "data-collector__secret_accessor", member = "serviceAccount:${var.service_account_emails["data-collector"]}", role = "roles/secretmanager.secretAccessor" },
    # feature-engineering
    { key = "feature-engineering__pubsub_subscriber", member = "serviceAccount:${var.service_account_emails["feature-engineering"]}", role = "roles/pubsub.subscriber" },
    { key = "feature-engineering__pubsub_publisher", member = "serviceAccount:${var.service_account_emails["feature-engineering"]}", role = "roles/pubsub.publisher" },
    # signal-generator
    { key = "signal-generator__pubsub_subscriber", member = "serviceAccount:${var.service_account_emails["signal-generator"]}", role = "roles/pubsub.subscriber" },
    { key = "signal-generator__pubsub_publisher", member = "serviceAccount:${var.service_account_emails["signal-generator"]}", role = "roles/pubsub.publisher" },
    { key = "signal-generator__secret_accessor", member = "serviceAccount:${var.service_account_emails["signal-generator"]}", role = "roles/secretmanager.secretAccessor" },
    # portfolio-planner
    { key = "portfolio-planner__pubsub_subscriber", member = "serviceAccount:${var.service_account_emails["portfolio-planner"]}", role = "roles/pubsub.subscriber" },
    { key = "portfolio-planner__pubsub_publisher", member = "serviceAccount:${var.service_account_emails["portfolio-planner"]}", role = "roles/pubsub.publisher" },
    # risk-guard
    { key = "risk-guard__pubsub_subscriber", member = "serviceAccount:${var.service_account_emails["risk-guard"]}", role = "roles/pubsub.subscriber" },
    { key = "risk-guard__pubsub_publisher", member = "serviceAccount:${var.service_account_emails["risk-guard"]}", role = "roles/pubsub.publisher" },
    # execution
    { key = "execution__pubsub_subscriber", member = "serviceAccount:${var.service_account_emails["execution"]}", role = "roles/pubsub.subscriber" },
    { key = "execution__pubsub_publisher", member = "serviceAccount:${var.service_account_emails["execution"]}", role = "roles/pubsub.publisher" },
    { key = "execution__secret_accessor", member = "serviceAccount:${var.service_account_emails["execution"]}", role = "roles/secretmanager.secretAccessor" },
    # audit-log
    { key = "audit-log__pubsub_subscriber", member = "serviceAccount:${var.service_account_emails["audit-log"]}", role = "roles/pubsub.subscriber" },
    { key = "audit-log__pubsub_publisher", member = "serviceAccount:${var.service_account_emails["audit-log"]}", role = "roles/pubsub.publisher" },
    # insight-collector
    { key = "insight-collector__pubsub_subscriber", member = "serviceAccount:${var.service_account_emails["insight-collector"]}", role = "roles/pubsub.subscriber" },
    { key = "insight-collector__pubsub_publisher", member = "serviceAccount:${var.service_account_emails["insight-collector"]}", role = "roles/pubsub.publisher" },
    { key = "insight-collector__secret_accessor", member = "serviceAccount:${var.service_account_emails["insight-collector"]}", role = "roles/secretmanager.secretAccessor" },
    # agent-orchestrator
    { key = "agent-orchestrator__pubsub_subscriber", member = "serviceAccount:${var.service_account_emails["agent-orchestrator"]}", role = "roles/pubsub.subscriber" },
    { key = "agent-orchestrator__pubsub_publisher", member = "serviceAccount:${var.service_account_emails["agent-orchestrator"]}", role = "roles/pubsub.publisher" },
    { key = "agent-orchestrator__secret_accessor", member = "serviceAccount:${var.service_account_emails["agent-orchestrator"]}", role = "roles/secretmanager.secretAccessor" },
    # hypothesis-lab
    { key = "hypothesis-lab__pubsub_subscriber", member = "serviceAccount:${var.service_account_emails["hypothesis-lab"]}", role = "roles/pubsub.subscriber" },
    { key = "hypothesis-lab__pubsub_publisher", member = "serviceAccount:${var.service_account_emails["hypothesis-lab"]}", role = "roles/pubsub.publisher" },
  ]
}

# Common roles for all runtime service accounts
resource "google_project_iam_member" "common" {
  for_each = { for binding in local.common_bindings : binding.key => binding }

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}

# Additional project-level roles per service
resource "google_project_iam_member" "additional" {
  for_each = { for binding in local.additional_project_bindings : binding.key => binding }

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}

# Bucket-level IAM for data-collector (raw_market_data bucket)
resource "google_storage_bucket_iam_member" "data_collector_raw_market_data_admin" {
  bucket = var.bucket_names["raw-market-data"]
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.service_account_emails["data-collector"]}"
}

# Bucket-level IAM for feature-engineering
resource "google_storage_bucket_iam_member" "feature_engineering_raw_market_data_viewer" {
  bucket = var.bucket_names["raw-market-data"]
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.service_account_emails["feature-engineering"]}"
}

resource "google_storage_bucket_iam_member" "feature_engineering_feature_store_admin" {
  bucket = var.bucket_names["feature-store"]
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.service_account_emails["feature-engineering"]}"
}

# Bucket-level IAM for signal-generator
resource "google_storage_bucket_iam_member" "signal_generator_feature_store_viewer" {
  bucket = var.bucket_names["feature-store"]
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.service_account_emails["signal-generator"]}"
}

resource "google_storage_bucket_iam_member" "signal_generator_signal_store_admin" {
  bucket = var.bucket_names["signal-store"]
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.service_account_emails["signal-generator"]}"
}

# Bucket-level IAM for insight-collector
resource "google_storage_bucket_iam_member" "insight_collector_insight_raw_admin" {
  bucket = var.bucket_names["insight-raw"]
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.service_account_emails["insight-collector"]}"
}

resource "google_storage_bucket_iam_member" "insight_collector_insight_processed_admin" {
  bucket = var.bucket_names["insight-processed"]
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.service_account_emails["insight-collector"]}"
}

# Bucket-level IAM for agent-orchestrator
resource "google_storage_bucket_iam_member" "agent_orchestrator_hypothesis_reports_admin" {
  bucket = var.bucket_names["hypothesis-reports"]
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.service_account_emails["agent-orchestrator"]}"
}

# Bucket-level IAM for hypothesis-lab
resource "google_storage_bucket_iam_member" "hypothesis_lab_backtest_artifacts_admin" {
  bucket = var.bucket_names["backtest-artifacts"]
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.service_account_emails["hypothesis-lab"]}"
}

resource "google_storage_bucket_iam_member" "hypothesis_lab_demo_artifacts_admin" {
  bucket = var.bucket_names["demo-artifacts"]
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.service_account_emails["hypothesis-lab"]}"
}

# NOTE: BFF SA -> risk-guard run.invoker binding is defined in the root module
# (envs/stg/main.tf or envs/prod/main.tf) to avoid circular dependency with
# cloud-run-services module. See INF-003 section 6.3.

# Scheduler SA: permission to run Cloud Run Jobs
# Uses Cloud Run Jobs invoker role on the project level
resource "google_project_iam_member" "scheduler_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${var.service_account_emails["scheduler"]}"
}

# Cloud Scheduler サービスエージェントが SA を impersonate するために必要
# OAuth token 生成時に serviceAccountTokenCreator 権限が必要
data "google_project" "current" {
  project_id = var.project_id
}

resource "google_service_account_iam_member" "scheduler_token_creator" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.service_account_emails["scheduler"]}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
}
