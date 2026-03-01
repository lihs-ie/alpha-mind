terraform {
  required_version = ">= 1.5"

  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ── Notification Channels ──────────────────────────────────────────────────────

module "notification_channels" {
  source     = "../../modules/notification-channels"
  project_id = var.project_id

  channels = {
    page = {
      display_name = "Alpha Mind Page Alert (${var.environment})"
      type         = "email"
      labels = {
        email_address = var.alert_email_page
      }
    }
    ticket = {
      display_name = "Alpha Mind Ticket Alert (${var.environment})"
      type         = "email"
      labels = {
        email_address = var.alert_email_ticket
      }
    }
    billing = {
      display_name = "Alpha Mind Billing Alert (${var.environment})"
      type         = "email"
      labels = {
        email_address = var.budget_notification_email
      }
    }
  }
}

# ── Custom Services ────────────────────────────────────────────────────────────
# One custom service per SLO-tracked service

module "custom_services" {
  source     = "../../modules/custom-services"
  project_id = var.project_id

  services = {
    bff = {
      display_name = "BFF API Gateway (${var.environment})"
    }
    data-collector = {
      display_name = "Data Collector (${var.environment})"
    }
    signal-generator = {
      display_name = "Signal Generator (${var.environment})"
    }
    execution = {
      display_name = "Execution (${var.environment})"
    }
    risk-guard = {
      display_name = "Risk Guard (${var.environment})"
    }
    insight-collector = {
      display_name = "Insight Collector (${var.environment})"
    }
    hypothesis-lab = {
      display_name = "Hypothesis Lab (${var.environment})"
    }
  }
}

# ── SLOs ───────────────────────────────────────────────────────────────────────

module "slos" {
  source     = "../../modules/slos"
  project_id = var.project_id

  custom_service_names = module.custom_services.service_names

  depends_on = [module.custom_services]
}

# ── Burn Rate Alerts ───────────────────────────────────────────────────────────

module "burn_rate_alerts" {
  source     = "../../modules/burn-rate-alerts"
  project_id = var.project_id

  slo_names            = module.slos.slo_names
  page_channel_names   = [module.notification_channels.channel_names["page"]]
  ticket_channel_names = [module.notification_channels.channel_names["ticket"]]

  depends_on = [module.slos]
}

# ── Billing Budget ────────────────────────────────────────────────────────────

module "billing_budget" {
  source     = "../../modules/billing-budget"
  project_id = var.project_id

  billing_account_id         = var.billing_account_id
  environment                = var.environment
  budget_amount              = var.monthly_budget_amount
  currency_code              = var.budget_currency_code
  threshold_percentages      = var.budget_threshold_percentages
  notification_channel_names = [module.notification_channels.channel_names["billing"]]
}

# ── Supplemental Monitor Alerts ────────────────────────────────────────────────

module "supplemental_monitor_alerts" {
  source     = "../../modules/supplemental-monitor-alerts"
  project_id = var.project_id

  page_channel_names   = [module.notification_channels.channel_names["page"]]
  ticket_channel_names = [module.notification_channels.channel_names["ticket"]]
}
