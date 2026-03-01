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

variable "github_repository" {
  description = "GitHub repository in owner/repo format for Workload Identity Federation"
  type        = string
  default     = "lihs-ie/alpha-mind"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in 'owner/repo' format (e.g. 'lihs-ie/alpha-mind')."
  }
}
