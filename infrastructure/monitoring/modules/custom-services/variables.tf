variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "services" {
  description = "Map of service ID to service display name"
  type = map(object({
    display_name = string
  }))
}
