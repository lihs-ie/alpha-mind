variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "alpha-mind-stg"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "asia-northeast1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "stg"
}

variable "billing_account_id" {
  description = "GCP billing account ID (pass via TF_VAR_billing_account_id)"
  type        = string
  sensitive   = true
}

variable "budget_notification_email" {
  description = "Email address for billing budget alerts"
  type        = string
}

variable "monthly_budget_amount" {
  description = "Monthly budget amount in the specified currency"
  type        = number
  default     = 10000
}

variable "budget_currency_code" {
  description = "ISO 4217 currency code for the budget"
  type        = string
  default     = "JPY"
}

variable "budget_threshold_percentages" {
  description = "List of threshold percentages (0-100) at which to send notifications"
  type        = list(number)
  default     = [20, 50, 80, 100]
}

variable "alert_email_page" {
  description = "Email address for page-level alerts (high priority)"
  type        = string
}

variable "alert_email_ticket" {
  description = "Email address for ticket-level alerts (lower priority)"
  type        = string
}
