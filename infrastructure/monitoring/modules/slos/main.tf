# slos: SLO definitions from slo-query-spec.json
# Generates google_monitoring_slo for each SLO in the spec

locals {
  query_spec = jsondecode(file("${path.module}/../../generated/slo-query-spec.json"))

  # Build SLO map keyed by SLO ID
  slos_map = { for slo in local.query_spec.slos : slo.id => slo }
}

resource "google_monitoring_slo" "slos" {
  for_each = local.slos_map

  project      = var.project_id
  service      = var.custom_service_names[var.slo_service_mapping[each.key]]
  slo_id       = lower(replace(each.key, "-", "_"))
  display_name = each.value.name
  goal         = each.value.objective
  # 30-day rolling window
  rolling_period_days = 30

  request_based_sli {
    good_total_ratio {
      good_service_filter = join(" AND ", compact([
        "metric.type=\"${each.value.numerator.metricType}\"",
        "resource.type=\"${each.value.numerator.resourceType}\"",
        try(each.value.numerator.filter, "") != "" ? each.value.numerator.filter : null,
      ]))
      total_service_filter = join(" AND ", compact([
        "metric.type=\"${each.value.denominator.metricType}\"",
        "resource.type=\"${each.value.denominator.resourceType}\"",
        try(each.value.denominator.filter, "") != "" ? each.value.denominator.filter : null,
      ]))
    }
  }
}
