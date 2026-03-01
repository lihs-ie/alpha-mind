output "slo_names" {
  description = "Map of SLO ID to resource name"
  value       = { for k, v in google_monitoring_slo.slos : k => v.name }
}

output "slo_ids" {
  description = "Map of SLO ID to SLO ID string"
  value       = { for k, v in google_monitoring_slo.slos : k => v.slo_id }
}
