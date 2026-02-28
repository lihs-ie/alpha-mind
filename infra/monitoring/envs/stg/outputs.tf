output "notification_channel_names" {
  description = "Map of channel key to notification channel resource name"
  value       = module.notification_channels.channel_names
}

output "custom_service_ids" {
  description = "Map of service key to custom service ID"
  value       = module.custom_services.service_ids
}

output "slo_names" {
  description = "Map of SLO ID to SLO resource name"
  value       = module.slos.slo_names
}

output "burn_rate_alert_policy_names" {
  description = "Map of alert key to alert policy name"
  value       = module.burn_rate_alerts.alert_policy_names
}

output "supplemental_warning_alert_policy_names" {
  description = "Map of monitor ID to warning alert policy resource name"
  value       = module.supplemental_monitor_alerts.warning_alert_policy_names
}

output "supplemental_critical_alert_policy_names" {
  description = "Map of monitor ID to critical alert policy resource name"
  value       = module.supplemental_monitor_alerts.critical_alert_policy_names
}
