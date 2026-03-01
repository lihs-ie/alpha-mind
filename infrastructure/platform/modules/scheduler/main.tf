# scheduler: Cloud Scheduler jobs per INF-005
# STG: all jobs created as PAUSED (enabled only for verification)
# Naming: sch-{purpose}-{env}

resource "google_cloud_scheduler_job" "jobs" {
  for_each = var.scheduler_jobs

  project   = var.project_id
  region    = var.region
  name      = "sch-${each.key}-${var.environment}"
  schedule  = each.value.cron
  time_zone = "Asia/Tokyo"

  # STG starts paused per INF-005 section 8.3
  paused = var.paused

  retry_config {
    retry_count          = 3
    min_backoff_duration = "60s"
    max_backoff_duration = "600s"
  }

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${each.value.job_name}:run"

    oauth_token {
      service_account_email = each.value.service_account_email
    }
  }
}
