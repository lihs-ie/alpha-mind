# cloud-run-services: Cloud Run Service definitions
# Parameters per INF-002 section 5.1
# Services: bff, audit-log, portfolio-planner, risk-guard, execution, agent-orchestrator, frontend-sol

resource "google_cloud_run_v2_service" "services" {
  for_each = var.services

  project  = var.project_id
  name     = each.key
  location = var.region

  ingress = each.value.ingress

  template {
    service_account = each.value.service_account_email

    scaling {
      min_instance_count = each.value.min_instances
      max_instance_count = each.value.max_instances
    }

    timeout = "${each.value.request_timeout_seconds}s"

    max_instance_request_concurrency = each.value.concurrency

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

  lifecycle {
    # Image is managed by CI/CD pipeline, not Terraform
    ignore_changes = [
      template[0].containers[0].image,
    ]
  }
}
