# supplemental-monitor-alerts: MON-001 to MON-004 supplemental monitors
# These are not SLO-based, they use threshold-based alert policies
#
# Monitor shapes:
#   - ratio (MON-001, MON-004): numerator/denominator → condition_threshold + denominator_filter
#   - formula (MON-002): avg_7d - avg_30d → condition_monitoring_query_language (MQL)
#   - simple (MON-003): single metric count → condition_threshold

locals {
  query_spec = jsondecode(file("${path.module}/../../generated/slo-query-spec.json"))

  supplemental_monitors = { for mon in local.query_spec.supplementalMonitors : mon.id => mon }

  # モニターを形状別に分類する
  ratio_monitors = {
    for id, mon in local.supplemental_monitors : id => mon
    if try(mon.numerator, null) != null && try(mon.denominator, null) != null
  }

  formula_monitors = {
    for id, mon in local.supplemental_monitors : id => mon
    if try(mon.formula, null) != null
  }

  simple_monitors = {
    for id, mon in local.supplemental_monitors : id => mon
    if try(mon.metric, null) != null
  }
}

# ── Ratio monitors (MON-001, MON-004) ───────────────────────────────────────

resource "google_monitoring_alert_policy" "ratio_warnings" {
  for_each = local.ratio_monitors

  project      = var.project_id
  display_name = "Supplemental Monitor WARNING: ${each.key} - ${each.value.name}"
  combiner     = "OR"

  conditions {
    display_name = "${each.value.name} >= warning threshold"

    condition_threshold {
      filter             = "metric.type=\"${each.value.numerator.metricType}\" AND resource.type=\"${each.value.numerator.resourceType}\""
      denominator_filter = "metric.type=\"${each.value.denominator.metricType}\" AND resource.type=\"${each.value.denominator.resourceType}\""
      comparison         = "COMPARISON_GT"
      threshold_value    = each.value.thresholds.warning
      duration           = "0s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }

      denominator_aggregations {
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

resource "google_monitoring_alert_policy" "ratio_criticals" {
  for_each = local.ratio_monitors

  project      = var.project_id
  display_name = "Supplemental Monitor CRITICAL: ${each.key} - ${each.value.name}"
  combiner     = "OR"

  conditions {
    display_name = "${each.value.name} >= critical threshold"

    condition_threshold {
      filter             = "metric.type=\"${each.value.numerator.metricType}\" AND resource.type=\"${each.value.numerator.resourceType}\""
      denominator_filter = "metric.type=\"${each.value.denominator.metricType}\" AND resource.type=\"${each.value.denominator.resourceType}\""
      comparison         = "COMPARISON_GT"
      threshold_value    = each.value.thresholds.critical
      duration           = "0s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }

      denominator_aggregations {
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

# ── Formula monitors (MON-002) ──────────────────────────────────────────────

resource "google_monitoring_alert_policy" "formula_warnings" {
  for_each = local.formula_monitors

  project      = var.project_id
  display_name = "Supplemental Monitor WARNING: ${each.key} - ${each.value.name}"
  combiner     = "OR"

  conditions {
    display_name = "${each.value.name} below warning threshold"

    condition_monitoring_query_language {
      duration = "0s"
      query    = <<-EOT
        {
          fetch global
          | metric '${each.value.left.metricType}'
          | group_by [], [val: mean(value.cost_adjusted_sharpe)]
          | window(${each.value.left.alignmentWindow})
          ;
          fetch global
          | metric '${each.value.right.metricType}'
          | group_by [], [val: mean(value.cost_adjusted_sharpe)]
          | window(${each.value.right.alignmentWindow})
        }
        | join
        | value [diff: val_0 - val_1]
        | condition diff < ${each.value.thresholds.warning}
      EOT
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

resource "google_monitoring_alert_policy" "formula_criticals" {
  for_each = local.formula_monitors

  project      = var.project_id
  display_name = "Supplemental Monitor CRITICAL: ${each.key} - ${each.value.name}"
  combiner     = "OR"

  conditions {
    display_name = "${each.value.name} below critical threshold"

    condition_monitoring_query_language {
      duration = "0s"
      query    = <<-EOT
        {
          fetch global
          | metric '${each.value.left.metricType}'
          | group_by [], [val: mean(value.cost_adjusted_sharpe)]
          | window(${each.value.left.alignmentWindow})
          ;
          fetch global
          | metric '${each.value.right.metricType}'
          | group_by [], [val: mean(value.cost_adjusted_sharpe)]
          | window(${each.value.right.alignmentWindow})
        }
        | join
        | value [diff: val_0 - val_1]
        | condition diff < ${each.value.thresholds.critical}
      EOT
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

# ── Simple metric monitors (MON-003) ────────────────────────────────────────

resource "google_monitoring_alert_policy" "simple_warnings" {
  for_each = local.simple_monitors

  project      = var.project_id
  display_name = "Supplemental Monitor WARNING: ${each.key} - ${each.value.name}"
  combiner     = "OR"

  conditions {
    display_name = "${each.value.name} >= warning threshold"

    condition_threshold {
      filter          = "metric.type=\"${each.value.metric.metricType}\" AND resource.type=\"${each.value.metric.resourceType}\""
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.thresholds.warning
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

resource "google_monitoring_alert_policy" "simple_criticals" {
  for_each = local.simple_monitors

  project      = var.project_id
  display_name = "Supplemental Monitor CRITICAL: ${each.key} - ${each.value.name}"
  combiner     = "OR"

  conditions {
    display_name = "${each.value.name} >= critical threshold"

    condition_threshold {
      filter          = "metric.type=\"${each.value.metric.metricType}\" AND resource.type=\"${each.value.metric.resourceType}\""
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.thresholds.critical
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
