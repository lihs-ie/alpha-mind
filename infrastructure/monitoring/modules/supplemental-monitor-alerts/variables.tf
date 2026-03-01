variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "page_channel_names" {
  description = "List of notification channel resource names for page-level alerts"
  type        = list(string)
}

variable "ticket_channel_names" {
  description = "List of notification channel resource names for ticket-level alerts"
  type        = list(string)
}
