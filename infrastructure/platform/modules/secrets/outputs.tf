output "secret_ids" {
  description = "Map of secret key to Secret Manager secret ID"
  value       = { for k, v in google_secret_manager_secret.secrets : k => v.secret_id }
}

output "secret_names" {
  description = "Map of secret key to Secret Manager full resource name"
  value       = { for k, v in google_secret_manager_secret.secrets : k => v.name }
}
