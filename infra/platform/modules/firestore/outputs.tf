output "database_name" {
  description = "Firestore database name"
  value       = google_firestore_database.database.name
}

output "database_id" {
  description = "Firestore database resource ID"
  value       = google_firestore_database.database.id
}

output "index_ids" {
  description = "Map of index key to Firestore index ID"
  value       = { for k, v in google_firestore_index.indexes : k => v.id }
}
