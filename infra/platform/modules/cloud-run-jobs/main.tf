# cloud-run-jobs: Cloud Run Job definitions
# Parameters per INF-002 section 5.2
# Jobs: data-collector, feature-engineering, signal-generator, insight-collector, hypothesis-lab

resource "google_cloud_run_v2_job" "jobs" {
  for_each = var.jobs

  project  = var.project_id
  name     = each.key
  location = var.region

  template {
    task_count  = each.value.task_count
    parallelism = each.value.parallelism

    template {
      service_account = each.value.service_account_email
      max_retries     = each.value.max_retries

      timeout = "${each.value.task_timeout_seconds}s"

      containers {
        image = each.value.image

        resources {
          limits = {
            cpu    = each.value.cpu
            memory = each.value.memory
          }
        }

        dynamic "env" {
          for_each = each.value.env_vars
          content {
            name  = env.key
            value = env.value
          }
        }
      }
    }
  }

  lifecycle {
    # Image is managed by CI/CD pipeline, not Terraform
    ignore_changes = [
      template[0].template[0].containers[0].image,
    ]
  }
}
