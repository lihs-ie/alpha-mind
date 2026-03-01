output "enabled_services" {
  description = "Map of enabled GCP services"
  value       = { for k, v in google_project_service.services : k => v.service }
}
