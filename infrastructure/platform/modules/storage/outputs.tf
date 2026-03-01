output "bucket_names" {
  description = "Map of bucket logical name to GCS bucket name"
  value       = { for k, v in google_storage_bucket.buckets : k => v.name }
}

output "bucket_urls" {
  description = "Map of bucket logical name to GCS bucket URL"
  value       = { for k, v in google_storage_bucket.buckets : k => v.url }
}
