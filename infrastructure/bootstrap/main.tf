# Bootstrap: Terraform state bucket and CI/CD service accounts
# This module must be applied before all other modules.
# Run: terraform init && terraform apply (no remote backend - local state only for bootstrap)

terraform {
  required_version = ">= 1.14"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Terraform state bucket for platform (cloud-run, pubsub, storage, etc.)
resource "google_storage_bucket" "terraform_state_platform" {
  name                        = "tfstate-alpha-mind-${var.environment}-platform"
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      # Keep at least 30 versions per object; old non-current versions expire after 90 days
      days_since_noncurrent_time = 90
      num_newer_versions         = 30
    }
  }
}

# Terraform state bucket for monitoring (SLOs, alert policies)
resource "google_storage_bucket" "terraform_state_monitoring" {
  name                        = "tfstate-alpha-mind-${var.environment}-monitoring"
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      days_since_noncurrent_time = 90
      num_newer_versions         = 30
    }
  }
}

# CI/CD service account for STG build and deploy
resource "google_service_account" "cicd" {
  account_id   = "sa-cicd-${var.environment}"
  display_name = "CI/CD Service Account (${var.environment})"
  description  = "Used by CI/CD pipeline to build and deploy services to ${var.environment}"
}

# Allow CI/CD SA to write objects to state buckets (for plan/apply)
resource "google_storage_bucket_iam_member" "cicd_platform_state_writer" {
  bucket = google_storage_bucket.terraform_state_platform.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cicd.email}"
}

resource "google_storage_bucket_iam_member" "cicd_monitoring_state_writer" {
  bucket = google_storage_bucket.terraform_state_monitoring.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cicd.email}"
}

# CI/CD roles: Artifact Registry writer + Cloud Run admin + SA user
resource "google_project_iam_member" "cicd_artifact_registry_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cicd.email}"
}

resource "google_project_iam_member" "cicd_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cicd.email}"
}

resource "google_project_iam_member" "cicd_iam_service_account_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cicd.email}"
}
