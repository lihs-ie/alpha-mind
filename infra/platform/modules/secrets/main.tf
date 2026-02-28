# secrets: Secret Manager secret metadata per INF-006
# Secret values are NOT managed by Terraform (populated separately)
# Naming: {env}-{service}-{key}

locals {
  # Secret matrix per INF-006 section 9.2
  # key = secret ID suffix after {env}-
  secrets = {
    "bff-oidc-client-secret"                 = { service = "bff", required = true }
    "bff-jwt-private-key"                    = { service = "bff", required = true }
    "bff-jwt-public-key"                     = { service = "bff", required = true }
    "data-collector-jquants-api-key"         = { service = "data-collector", required = true }
    "data-collector-alpaca-api-key"          = { service = "data-collector", required = false }
    "data-collector-alpaca-api-secret"       = { service = "data-collector", required = false }
    "execution-broker-api-key"               = { service = "execution", required = true }
    "execution-broker-api-secret"            = { service = "execution", required = true }
    "insight-collector-x-api-bearer-token"   = { service = "insight-collector", required = false }
    "insight-collector-youtube-api-key"      = { service = "insight-collector", required = false }
    "agent-orchestrator-llm-api-key"         = { service = "agent-orchestrator", required = true }
    "signal-generator-mlflow-tracking-token" = { service = "signal-generator", required = false }
  }
}

resource "google_secret_manager_secret" "secrets" {
  for_each = local.secrets

  project   = var.project_id
  secret_id = "${var.environment}-${each.key}"

  replication {
    auto {}
  }

  labels = {
    service     = each.value.service
    environment = var.environment
    required    = tostring(each.value.required)
  }
}
