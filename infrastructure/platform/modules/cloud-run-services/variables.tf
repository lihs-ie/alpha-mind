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

variable "services" {
  description = "Map of Cloud Run service configurations"
  type = map(object({
    cpu                     = string
    memory                  = string
    request_timeout_seconds = number
    concurrency             = number
    min_instances           = number
    max_instances           = number
    ingress                 = string
    service_account_email   = string
    image                   = string
    env_vars                = map(string)
  }))
}
