variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "custom_service_names" {
  description = "Map of service key to custom service resource name (from custom-services module)"
  type        = map(string)
}

variable "slo_service_mapping" {
  description = "Map of SLO ID to service key (used to look up custom_service_names)"
  type        = map(string)
  default = {
    "SLO-001" = "bff"
    "SLO-002" = "data-collector"
    "SLO-003" = "signal-generator"
    "SLO-004" = "execution"
    "SLO-005" = "risk-guard"
    "SLO-006" = "insight-collector"
    "SLO-007" = "hypothesis-lab"
  }
}
