output "job_names" {
  description = "Map of scheduler key to Cloud Scheduler job name"
  value       = { for k, v in google_cloud_scheduler_job.jobs : k => v.name }
}
