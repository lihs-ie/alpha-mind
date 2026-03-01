output "service_urls" {
  description = "Map of service name to Cloud Run service URL"
  value       = { for k, v in google_cloud_run_v2_service.services : k => v.uri }
}

output "service_names" {
  description = "Map of service name to Cloud Run service name"
  value       = { for k, v in google_cloud_run_v2_service.services : k => v.name }
}
