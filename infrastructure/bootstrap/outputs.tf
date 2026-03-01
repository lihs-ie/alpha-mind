output "platform_state_bucket" {
  description = "GCS bucket name for platform Terraform state"
  value       = google_storage_bucket.terraform_state_platform.name
}

output "monitoring_state_bucket" {
  description = "GCS bucket name for monitoring Terraform state"
  value       = google_storage_bucket.terraform_state_monitoring.name
}

output "cicd_service_account_email" {
  description = "CI/CD service account email"
  value       = google_service_account.cicd.email
}

output "workload_identity_provider" {
  description = "Workload Identity Provider resource name for GitHub Actions"
  value       = google_iam_workload_identity_pool_provider.github.name
}
