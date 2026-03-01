variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "environment" {
  description = "Environment name (stg or prod)"
  type        = string
}

variable "paused" {
  description = "Whether to create scheduler jobs in paused state (true for STG)"
  type        = bool
  default     = true
}

variable "scheduler_jobs" {
  description = "Map of scheduler job configurations"
  type = map(object({
    cron                  = string
    job_name              = string
    service_account_email = string
  }))
}
