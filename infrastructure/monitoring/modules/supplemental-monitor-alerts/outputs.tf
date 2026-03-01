output "warning_alert_policy_names" {
  description = "Map of monitor ID to warning alert policy resource name"
  value = merge(
    { for k, v in google_monitoring_alert_policy.ratio_warnings : k => v.name },
    { for k, v in google_monitoring_alert_policy.formula_warnings : k => v.name },
    { for k, v in google_monitoring_alert_policy.simple_warnings : k => v.name },
  )
}

output "critical_alert_policy_names" {
  description = "Map of monitor ID to critical alert policy resource name"
  value = merge(
    { for k, v in google_monitoring_alert_policy.ratio_criticals : k => v.name },
    { for k, v in google_monitoring_alert_policy.formula_criticals : k => v.name },
    { for k, v in google_monitoring_alert_policy.simple_criticals : k => v.name },
  )
}
