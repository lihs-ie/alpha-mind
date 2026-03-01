# project-services: Enable required GCP APIs
# All APIs needed across Cloud Run, Pub/Sub, Firestore, Secret Manager, etc.

resource "google_project_service" "services" {
  for_each = toset(var.services)

  project                    = var.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}
