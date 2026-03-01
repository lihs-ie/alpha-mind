# custom-services: Cloud Monitoring custom service definitions for SLO tracking
# One custom service per SLO-enabled service

resource "google_monitoring_custom_service" "services" {
  for_each = var.services

  project      = var.project_id
  service_id   = each.key
  display_name = each.value.display_name
}
