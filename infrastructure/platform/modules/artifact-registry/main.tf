# artifact-registry: Docker repository for container images
# Images path: {region}-docker.pkg.dev/{project}/alpha-mind-app/{service}

resource "google_artifact_registry_repository" "application" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = "Docker repository for alpha-mind application services (${var.environment})"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-recent-tags"
    action = "KEEP"

    most_recent_versions {
      keep_count = var.keep_recent_image_count
    }
  }
}
