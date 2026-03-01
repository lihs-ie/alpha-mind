variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "billing_account_id" {
  description = "GCP billing account ID"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "Environment name (e.g. stg, prd)"
  type        = string
}

variable "budget_amount" {
  description = "Monthly budget amount in the specified currency"
  type        = number
}

variable "currency_code" {
  description = "ISO 4217 currency code for the budget"
  type        = string
  default     = "JPY"
}

variable "threshold_percentages" {
  description = "List of threshold percentages (0-100) at which to send notifications"
  type        = list(number)
  default     = [20, 50, 80, 100]
}

variable "notification_channel_names" {
  description = "List of notification channel resource names to receive budget alerts"
  type        = list(string)
}
