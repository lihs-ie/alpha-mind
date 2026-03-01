output "alert_policy_names" {
  description = "Map of alert key to alert policy resource name"
  value       = { for k, v in google_monitoring_alert_policy.burn_rate_alerts : k => v.name }
}
