# notification-channels: Alert notification channel definitions
# Separates page (high priority) and ticket (low priority) channels

resource "google_monitoring_notification_channel" "channels" {
  for_each = var.channels

  project      = var.project_id
  display_name = each.value.display_name
  type         = each.value.type

  labels = each.value.labels

  enabled = true
}
