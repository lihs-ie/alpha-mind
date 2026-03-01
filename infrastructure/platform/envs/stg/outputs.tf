output "service_account_emails" {
  description = "Map of service name to service account email"
  value       = module.service_accounts.emails
}

output "cloud_run_service_urls" {
  description = "Map of service name to Cloud Run URL"
  value       = module.cloud_run_services.service_urls
}

output "storage_bucket_names" {
  description = "Map of bucket logical name to GCS bucket name"
  value       = module.storage.bucket_names
}

output "pubsub_topic_ids" {
  description = "Map of event type to Pub/Sub topic ID"
  value       = module.pubsub.topic_ids
}

output "secret_ids" {
  description = "Map of secret key to Secret Manager secret ID"
  value       = module.secrets.secret_ids
}

output "firestore_database_name" {
  description = "Firestore database name"
  value       = module.firestore.database_name
}

output "artifact_registry_url" {
  description = "Artifact Registry repository URL"
  value       = module.artifact_registry.repository_url
}
