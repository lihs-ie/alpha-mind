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

variable "repository_id" {
  description = "Artifact Registry repository ID"
  type        = string
  default     = "alpha-mind-app"
}

variable "keep_recent_image_count" {
  description = "Number of recent image versions to keep per tag"
  type        = number
  default     = 10
}
