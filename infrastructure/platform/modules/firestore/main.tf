# firestore: Firestore database, composite indexes, and TTL field configs
# 11 composite indexes + 3 TTL field overrides per firestore.indexes.json

resource "google_firestore_database" "database" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  # Optimistic concurrency for orders/settings/operations (version field)
  concurrency_mode = "OPTIMISTIC"

  # Point-in-time recovery: last 7 days
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
}

# Composite indexes per firestore.indexes.json
resource "google_firestore_index" "indexes" {
  for_each = {
    for def in var.composite_indexes :
    "${def.collection_group}__${join("_", [for f in def.fields : "${f.field_path}_${f.order}"])}" => def
  }

  project    = var.project_id
  database   = google_firestore_database.database.name
  collection = each.value.collection_group

  dynamic "fields" {
    for_each = each.value.fields
    content {
      field_path = fields.value.field_path
      order      = fields.value.order
    }
  }

  query_scope = each.value.query_scope
}

# TTL field configurations per firestore.indexes.json fieldOverrides
resource "google_firestore_field" "ttl_fields" {
  for_each = { for ttl in var.ttl_fields : "${ttl.collection_group}__${ttl.field_path}" => ttl }

  project    = var.project_id
  database   = google_firestore_database.database.name
  collection = each.value.collection_group
  field      = each.value.field_path

  ttl_config {}

  index_config {
    # Disable default indexes on TTL field to avoid write amplification
  }
}
