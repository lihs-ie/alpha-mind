variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "alpha-mind-prod"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "asia-northeast1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "artifact_registry_repository_id" {
  description = "Artifact Registry repository ID"
  type        = string
  default     = "alpha-mind-app"
}

# Placeholder image used before CI/CD pushes real images
variable "placeholder_image" {
  description = "Placeholder container image for initial deployment"
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}
