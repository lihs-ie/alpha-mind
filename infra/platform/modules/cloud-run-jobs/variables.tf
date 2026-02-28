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

variable "jobs" {
  description = "Map of Cloud Run job configurations"
  type = map(object({
    cpu                   = string
    memory                = string
    task_timeout_seconds  = number
    max_retries           = number
    task_count            = number
    parallelism           = number
    service_account_email = string
    image                 = string
    env_vars              = map(string)
  }))
}
