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

variable "alert_email_page" {
  description = "Email address for page-level alerts (high priority)"
  type        = string
}

variable "alert_email_ticket" {
  description = "Email address for ticket-level alerts (lower priority)"
  type        = string
}
