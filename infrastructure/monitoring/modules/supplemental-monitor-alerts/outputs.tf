output "warning_alert_policy_names" {
  description = "Map of monitor ID to warning alert policy resource name"
  value       = { for k, v in google_monitoring_alert_policy.supplemental_warnings : k => v.name }
}

output "critical_alert_policy_names" {
  description = "Map of monitor ID to critical alert policy resource name"
  value       = { for k, v in google_monitoring_alert_policy.supplemental_criticals : k => v.name }
}
