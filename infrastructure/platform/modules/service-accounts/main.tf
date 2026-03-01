# service-accounts: Runtime and ops service accounts
# Naming: sa-{service}-{env}@{project}.iam.gserviceaccount.com
# INF-003 compliant

locals {
  # Runtime service accounts for all microservices
  runtime_service_accounts = {
    bff = {
      display_name = "BFF API Gateway"
      description  = "Service account for BFF (API Gateway) Cloud Run service"
    }
    data-collector = {
      display_name = "Data Collector"
      description  = "Service account for data-collector Cloud Run Job"
    }
    feature-engineering = {
      display_name = "Feature Engineering"
      description  = "Service account for feature-engineering Cloud Run Job"
    }
    signal-generator = {
      display_name = "Signal Generator"
      description  = "Service account for signal-generator Cloud Run Job"
    }
    portfolio-planner = {
      display_name = "Portfolio Planner"
      description  = "Service account for portfolio-planner Cloud Run service"
    }
    risk-guard = {
      display_name = "Risk Guard"
      description  = "Service account for risk-guard Cloud Run service"
    }
    execution = {
      display_name = "Execution"
      description  = "Service account for execution Cloud Run service"
    }
    audit-log = {
      display_name = "Audit Log"
      description  = "Service account for audit-log Cloud Run service"
    }
    insight-collector = {
      display_name = "Insight Collector"
      description  = "Service account for insight-collector Cloud Run Job"
    }
    agent-orchestrator = {
      display_name = "Agent Orchestrator"
      description  = "Service account for agent-orchestrator Cloud Run service"
    }
    hypothesis-lab = {
      display_name = "Hypothesis Lab"
      description  = "Service account for hypothesis-lab Cloud Run Job"
    }
    frontend-sol = {
      display_name = "Frontend SOL"
      description  = "Service account for frontend-sol Cloud Run service"
    }
    scheduler = {
      display_name = "Scheduler"
      description  = "Service account for Cloud Scheduler to invoke Cloud Run Jobs"
    }
    ops = {
      display_name = "Operations"
      description  = "Service account for ops/monitoring tasks"
    }
  }
}

resource "google_service_account" "runtime" {
  for_each = local.runtime_service_accounts

  project      = var.project_id
  account_id   = "sa-${each.key}-${var.environment}"
  display_name = each.value.display_name
  description  = each.value.description
}
