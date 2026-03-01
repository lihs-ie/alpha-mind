# supplemental-monitor-alerts: MON-001 to MON-004 supplemental monitors
# These are not SLO-based, they use threshold-based alert policies

locals {
  query_spec = jsondecode(file("${path.module}/../../generated/slo-query-spec.json"))

  supplemental_monitors = { for mon in local.query_spec.supplementalMonitors : mon.id => mon }
}

resource "google_monitoring_alert_policy" "supplemental_warnings" {
  for_each = local.supplemental_monitors

  project      = var.project_id
  display_name = "Supplemental Monitor WARNING: ${each.key} - ${each.value.name}"
  combiner     = "OR"

  conditions {
    display_name = "${each.value.name} >= warning threshold"

    condition_threshold {
      # MON-001 and MON-004 use ratio (numerator/denominator)
      # MON-003 uses single metric count
      # MON-002 uses formula (avg_7d - avg_30d)
      # All are expressed as threshold conditions using custom metric filters
      filter = try(
        each.value.numerator != null,
        false
        ) ? "metric.type=\"${each.value.numerator.metricType}\" AND resource.type=\"${each.value.numerator.resourceType}\"" : try(
        each.value.metric != null,
        false
      ) ? "metric.type=\"${each.value.metric.metricType}\" AND resource.type=\"${each.value.metric.resourceType}\"" : "metric.type=\"${each.value.left.metricType}\" AND resource.type=\"${each.value.left.resourceType}\""

      comparison      = each.value.thresholds.warning < 0 ? "COMPARISON_LT" : "COMPARISON_GT"
      threshold_value = abs(each.value.thresholds.warning)
      duration        = "0s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.ticket_channel_names

  alert_strategy {
    auto_close = "604800s"
  }

  documentation {
    content   = "Monitor: ${each.key} | ${each.value.name} | Runbook: ${each.value.runbook}"
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "supplemental_criticals" {
  for_each = local.supplemental_monitors

  project      = var.project_id
  display_name = "Supplemental Monitor CRITICAL: ${each.key} - ${each.value.name}"
  combiner     = "OR"

  conditions {
    display_name = "${each.value.name} >= critical threshold"

    condition_threshold {
      filter = try(
        each.value.numerator != null,
        false
        ) ? "metric.type=\"${each.value.numerator.metricType}\" AND resource.type=\"${each.value.numerator.resourceType}\"" : try(
        each.value.metric != null,
        false
      ) ? "metric.type=\"${each.value.metric.metricType}\" AND resource.type=\"${each.value.metric.resourceType}\"" : "metric.type=\"${each.value.left.metricType}\" AND resource.type=\"${each.value.left.resourceType}\""

      comparison      = each.value.thresholds.critical < 0 ? "COMPARISON_LT" : "COMPARISON_GT"
      threshold_value = abs(each.value.thresholds.critical)
      duration        = "0s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.page_channel_names

  alert_strategy {
    auto_close = "604800s"
  }

  documentation {
    content   = "Monitor: ${each.key} | ${each.value.name} | Runbook: ${each.value.runbook}"
    mime_type = "text/markdown"
  }
}
