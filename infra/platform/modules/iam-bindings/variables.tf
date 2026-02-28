variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "environment" {
  description = "Environment name (stg or prod)"
  type        = string
}

variable "service_account_emails" {
  description = "Map of service name to service account email (from service-accounts module)"
  type        = map(string)
}

variable "bucket_names" {
  description = "Map of bucket logical name to GCS bucket name (from storage module)"
  type        = map(string)
}
