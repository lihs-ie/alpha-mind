output "job_names" {
  description = "Map of job key to Cloud Run job name"
  value       = { for k, v in google_cloud_run_v2_job.jobs : k => v.name }
}

output "job_ids" {
  description = "Map of job key to Cloud Run job resource ID"
  value       = { for k, v in google_cloud_run_v2_job.jobs : k => v.id }
}
