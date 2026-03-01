output "service_ids" {
  description = "Map of service key to custom service ID"
  value       = { for k, v in google_monitoring_custom_service.services : k => v.service_id }
}

output "service_names" {
  description = "Map of service key to custom service resource name"
  value       = { for k, v in google_monitoring_custom_service.services : k => v.name }
}
