variable "project_id" {
  description = "GCP project ID (e.g. alpha-mind-stg)"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "asia-northeast1"
}

variable "environment" {
  description = "Environment name (stg or prod)"
  type        = string

  validation {
    condition     = contains(["stg", "prod"], var.environment)
    error_message = "environment must be stg or prod."
  }
}
