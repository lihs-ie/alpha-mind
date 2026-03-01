# storage: GCS buckets for data lake and artifacts
# Buckets: raw-market-data, feature-store, signal-store, insight-raw, insight-processed,
#          hypothesis-reports, backtest-artifacts, demo-artifacts

locals {
  # Bucket definitions with lifecycle rules
  # Naming: alpha-mind-{purpose}-{env}
  buckets = {
    "raw-market-data" = {
      description        = "Raw market data from data-collector (Parquet)"
      lifecycle_age_days = 90
    }
    "feature-store" = {
      description        = "Engineered features from feature-engineering (Parquet)"
      lifecycle_age_days = 180
    }
    "signal-store" = {
      description        = "Generated signals from signal-generator (Parquet)"
      lifecycle_age_days = 180
    }
    "insight-raw" = {
      description        = "Raw insight data from insight-collector"
      lifecycle_age_days = 365
    }
    "insight-processed" = {
      description        = "Processed insights from insight-collector"
      lifecycle_age_days = 365
    }
    "hypothesis-reports" = {
      description        = "Hypothesis reports from agent-orchestrator (Markdown)"
      lifecycle_age_days = 730
    }
    "backtest-artifacts" = {
      description        = "Backtest artifacts from hypothesis-lab"
      lifecycle_age_days = 730
    }
    "demo-artifacts" = {
      description        = "Demo trade artifacts from hypothesis-lab"
      lifecycle_age_days = 730
    }
  }
}

resource "google_storage_bucket" "buckets" {
  for_each = local.buckets

  project                     = var.project_id
  name                        = "alpha-mind-${each.key}-${var.environment}"
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = each.value.lifecycle_age_days
    }
  }

  versioning {
    # Versioning disabled for data lake buckets to control costs
    # Backup via Firestore export and append-only Parquet pattern
    enabled = false
  }
}
