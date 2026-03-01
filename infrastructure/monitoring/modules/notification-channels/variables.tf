variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "channels" {
  description = "Map of notification channel configurations"
  type = map(object({
    display_name = string
    type         = string
    labels       = map(string)
  }))
}
