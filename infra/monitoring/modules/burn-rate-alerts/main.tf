# burn-rate-alerts: Burn rate alert policies for each SLO x burn rate tier
# 3 tiers x 7 SLOs = 21 alert policies total
# Tiers: ALERT-CRITICAL (14.4x), ALERT-HIGH (6x), ALERT-TICKET (1x)

locals {
  query_spec = jsondecode(file("${path.module}/../../generated/slo-query-spec.json"))

  burn_rate_policies = { for policy in local.query_spec.burnRatePolicies : policy.id => policy }

  # Cartesian product: SLO x burn rate tier
  alert_combinations = flatten([
    for slo_id, slo_name in var.slo_names : [
      for policy_id, policy in local.burn_rate_policies : {
        key          = "${slo_id}__${policy_id}"
        slo_id       = slo_id
        slo_name     = slo_name
        policy_id    = policy_id
        threshold    = policy.threshold
        short_window = policy.shortWindow
        long_window  = policy.longWindow
        severity     = policy.severity
      }
    ]
  ])

  alerts_map = { for alert in local.alert_combinations : alert.key => alert }
}

resource "google_monitoring_alert_policy" "burn_rate_alerts" {
  for_each = local.alerts_map

  project      = var.project_id
  display_name = "SLO Burn Rate: ${each.value.slo_id} ${each.value.policy_id}"
  combiner     = "AND"

  # Short window condition
  conditions {
    display_name = "Burn rate >= ${each.value.threshold} (short: ${each.value.short_window})"

    condition_threshold {
      filter          = "select_slo_burn_rate(\"${each.value.slo_name}\", \"${each.value.short_window}\")"
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = "0s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  # Long window condition
  conditions {
    display_name = "Burn rate >= ${each.value.threshold} (long: ${each.value.long_window})"

    condition_threshold {
      filter          = "select_slo_burn_rate(\"${each.value.slo_name}\", \"${each.value.long_window}\")"
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = "0s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = each.value.severity == "page" ? var.page_channel_names : var.ticket_channel_names

  alert_strategy {
    auto_close = "604800s" # 7 days
  }

  documentation {
    content   = "SLO: ${each.value.slo_id} | Burn rate: ${each.value.threshold}x | Window: ${each.value.short_window} / ${each.value.long_window}"
    mime_type = "text/markdown"
  }
}
