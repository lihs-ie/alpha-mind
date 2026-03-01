output "emails" {
  description = "Map of service name to service account email"
  value       = { for k, v in google_service_account.runtime : k => v.email }
}

output "service_account_ids" {
  description = "Map of service name to service account ID (for IAM bindings)"
  value       = { for k, v in google_service_account.runtime : k => v.account_id }
}
