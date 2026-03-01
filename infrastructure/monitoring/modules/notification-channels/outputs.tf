output "channel_names" {
  description = "Map of channel key to notification channel resource name"
  value       = { for k, v in google_monitoring_notification_channel.channels : k => v.name }
}
