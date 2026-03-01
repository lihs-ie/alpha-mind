variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region (Firestore location)"
  type        = string
}

variable "composite_indexes" {
  description = "List of composite index definitions from firestore.indexes.json"
  type = list(object({
    collection_group = string
    query_scope      = string
    fields = list(object({
      field_path = string
      order      = string
    }))
  }))
}

variable "ttl_fields" {
  description = "List of TTL field override definitions from firestore.indexes.json"
  type = list(object({
    collection_group = string
    field_path       = string
  }))
}
