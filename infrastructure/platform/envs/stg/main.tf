terraform {
  required_version = ">= 1.14"

  backend "gcs" {}

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

# ── Phase 1: Base ──────────────────────────────────────────────────────────────

module "project_services" {
  source     = "../../modules/project-services"
  project_id = var.project_id
}

module "artifact_registry" {
  source        = "../../modules/artifact-registry"
  project_id    = var.project_id
  region        = var.region
  environment   = var.environment
  repository_id = var.artifact_registry_repository_id
}

module "service_accounts" {
  source      = "../../modules/service-accounts"
  project_id  = var.project_id
  environment = var.environment

  depends_on = [module.project_services]
}

# ── Phase 2: Runtime ───────────────────────────────────────────────────────────

module "storage" {
  source      = "../../modules/storage"
  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  depends_on = [module.project_services]
}

module "iam_bindings" {
  source      = "../../modules/iam-bindings"
  project_id  = var.project_id
  environment = var.environment

  service_account_emails = module.service_accounts.emails
  bucket_names           = module.storage.bucket_names

  depends_on = [module.service_accounts, module.storage]
}

# BFF SA: invoke risk-guard service only (INF-003 section 6.3 scoped to risk-guard service)
resource "google_cloud_run_v2_service_iam_member" "bff_invoke_risk_guard" {
  project  = var.project_id
  location = var.region
  name     = module.cloud_run_services.service_names["risk-guard"]
  role     = "roles/run.invoker"
  member   = "serviceAccount:${module.service_accounts.emails["bff"]}"

  depends_on = [module.cloud_run_services, module.service_accounts]
}

module "cloud_run_services" {
  source      = "../../modules/cloud-run-services"
  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  services = {
    bff = {
      cpu                     = "1"
      memory                  = "512Mi"
      request_timeout_seconds = 30
      concurrency             = 80
      min_instances           = 0
      max_instances           = 10
      ingress                 = "INGRESS_TRAFFIC_ALL"
      service_account_email   = module.service_accounts.emails["bff"]
      image                   = var.placeholder_image
      env_vars = {
        APP_ENV             = var.environment
        GCP_PROJECT_ID      = var.project_id
        GCP_REGION          = var.region
        FIRESTORE_DATABASE  = "(default)"
        PUBSUB_TOPIC_PREFIX = "event-"
      }
    }
    audit-log = {
      cpu                     = "1"
      memory                  = "512Mi"
      request_timeout_seconds = 30
      concurrency             = 80
      min_instances           = 0
      max_instances           = 10
      ingress                 = "INGRESS_TRAFFIC_INTERNAL_ONLY"
      service_account_email   = module.service_accounts.emails["audit-log"]
      image                   = var.placeholder_image
      env_vars = {
        APP_ENV             = var.environment
        GCP_PROJECT_ID      = var.project_id
        GCP_REGION          = var.region
        FIRESTORE_DATABASE  = "(default)"
        PUBSUB_TOPIC_PREFIX = "event-"
      }
    }
    portfolio-planner = {
      cpu                     = "1"
      memory                  = "1Gi"
      request_timeout_seconds = 120
      concurrency             = 20
      min_instances           = 0
      max_instances           = 10
      ingress                 = "INGRESS_TRAFFIC_INTERNAL_ONLY"
      service_account_email   = module.service_accounts.emails["portfolio-planner"]
      image                   = var.placeholder_image
      env_vars = {
        APP_ENV             = var.environment
        GCP_PROJECT_ID      = var.project_id
        GCP_REGION          = var.region
        FIRESTORE_DATABASE  = "(default)"
        PUBSUB_TOPIC_PREFIX = "event-"
      }
    }
    risk-guard = {
      cpu                     = "1"
      memory                  = "512Mi"
      request_timeout_seconds = 10
      concurrency             = 20
      min_instances           = 0
      max_instances           = 20
      ingress                 = "INGRESS_TRAFFIC_INTERNAL_ONLY"
      service_account_email   = module.service_accounts.emails["risk-guard"]
      image                   = var.placeholder_image
      env_vars = {
        APP_ENV             = var.environment
        GCP_PROJECT_ID      = var.project_id
        GCP_REGION          = var.region
        FIRESTORE_DATABASE  = "(default)"
        PUBSUB_TOPIC_PREFIX = "event-"
      }
    }
    execution = {
      cpu                     = "1"
      memory                  = "1Gi"
      request_timeout_seconds = 60
      concurrency             = 10
      min_instances           = 0
      max_instances           = 10
      ingress                 = "INGRESS_TRAFFIC_INTERNAL_ONLY"
      service_account_email   = module.service_accounts.emails["execution"]
      image                   = var.placeholder_image
      env_vars = {
        APP_ENV             = var.environment
        GCP_PROJECT_ID      = var.project_id
        GCP_REGION          = var.region
        FIRESTORE_DATABASE  = "(default)"
        PUBSUB_TOPIC_PREFIX = "event-"
      }
    }
    agent-orchestrator = {
      cpu                     = "2"
      memory                  = "2Gi"
      request_timeout_seconds = 300
      concurrency             = 4
      min_instances           = 0
      max_instances           = 5
      ingress                 = "INGRESS_TRAFFIC_INTERNAL_ONLY"
      service_account_email   = module.service_accounts.emails["agent-orchestrator"]
      image                   = var.placeholder_image
      env_vars = {
        APP_ENV             = var.environment
        GCP_PROJECT_ID      = var.project_id
        GCP_REGION          = var.region
        FIRESTORE_DATABASE  = "(default)"
        PUBSUB_TOPIC_PREFIX = "event-"
      }
    }
    frontend = {
      cpu                     = "1"
      memory                  = "512Mi"
      request_timeout_seconds = 30
      concurrency             = 80
      min_instances           = 0
      max_instances           = 10
      ingress                 = "INGRESS_TRAFFIC_ALL"
      service_account_email   = module.service_accounts.emails["frontend"]
      image                   = var.placeholder_image
      env_vars = {
        APP_ENV      = var.environment
        BFF_BASE_URL = "https://staging.api.alpha-mind.dev"
      }
    }
  }

  depends_on = [module.service_accounts, module.iam_bindings]
}

module "cloud_run_jobs" {
  source      = "../../modules/cloud-run-jobs"
  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  jobs = {
    data-collector = {
      cpu                   = "2"
      memory                = "2Gi"
      task_timeout_seconds  = 1200
      max_retries           = 1
      task_count            = 1
      parallelism           = 1
      service_account_email = module.service_accounts.emails["data-collector"]
      image                 = var.placeholder_image
      env_vars = {
        APP_ENV             = var.environment
        GCP_PROJECT_ID      = var.project_id
        GCP_REGION          = var.region
        FIRESTORE_DATABASE  = "(default)"
        PUBSUB_TOPIC_PREFIX = "event-"
      }
    }
    feature-engineering = {
      cpu                   = "2"
      memory                = "4Gi"
      task_timeout_seconds  = 1800
      max_retries           = 1
      task_count            = 1
      parallelism           = 1
      service_account_email = module.service_accounts.emails["feature-engineering"]
      image                 = var.placeholder_image
      env_vars = {
        APP_ENV             = var.environment
        GCP_PROJECT_ID      = var.project_id
        GCP_REGION          = var.region
        FIRESTORE_DATABASE  = "(default)"
        PUBSUB_TOPIC_PREFIX = "event-"
      }
    }
    signal-generator = {
      cpu                   = "2"
      memory                = "2Gi"
      task_timeout_seconds  = 1200
      max_retries           = 1
      task_count            = 1
      parallelism           = 1
      service_account_email = module.service_accounts.emails["signal-generator"]
      image                 = var.placeholder_image
      env_vars = {
        APP_ENV             = var.environment
        GCP_PROJECT_ID      = var.project_id
        GCP_REGION          = var.region
        FIRESTORE_DATABASE  = "(default)"
        PUBSUB_TOPIC_PREFIX = "event-"
      }
    }
    insight-collector = {
      cpu                   = "2"
      memory                = "2Gi"
      task_timeout_seconds  = 1800
      max_retries           = 1
      task_count            = 1
      parallelism           = 1
      service_account_email = module.service_accounts.emails["insight-collector"]
      image                 = var.placeholder_image
      env_vars = {
        APP_ENV             = var.environment
        GCP_PROJECT_ID      = var.project_id
        GCP_REGION          = var.region
        FIRESTORE_DATABASE  = "(default)"
        PUBSUB_TOPIC_PREFIX = "event-"
      }
    }
    hypothesis-lab = {
      cpu                   = "4"
      memory                = "8Gi"
      task_timeout_seconds  = 7200
      max_retries           = 1
      task_count            = 1
      parallelism           = 1
      service_account_email = module.service_accounts.emails["hypothesis-lab"]
      image                 = var.placeholder_image
      env_vars = {
        APP_ENV             = var.environment
        GCP_PROJECT_ID      = var.project_id
        GCP_REGION          = var.region
        FIRESTORE_DATABASE  = "(default)"
        PUBSUB_TOPIC_PREFIX = "event-"
      }
    }
  }

  depends_on = [module.service_accounts, module.iam_bindings]
}

module "pubsub" {
  source      = "../../modules/pubsub"
  project_id  = var.project_id
  environment = var.environment

  depends_on = [module.project_services]
}

module "scheduler" {
  source      = "../../modules/scheduler"
  project_id  = var.project_id
  region      = var.region
  environment = var.environment
  paused      = true # STG: start paused per INF-005

  scheduler_jobs = {
    market-collect-weekday = {
      cron                  = "45 5 * * 1-5"
      job_name              = "data-collector"
      service_account_email = module.service_accounts.emails["scheduler"]
    }
    insight-collect-weekday = {
      cron                  = "0 6 * * 1-5"
      job_name              = "insight-collector"
      service_account_email = module.service_accounts.emails["scheduler"]
    }
  }

  depends_on = [module.cloud_run_jobs]
}

module "secrets" {
  source      = "../../modules/secrets"
  project_id  = var.project_id
  environment = var.environment

  depends_on = [module.project_services]
}

module "firestore" {
  source     = "../../modules/firestore"
  project_id = var.project_id
  region     = var.region

  composite_indexes = [
    {
      collection_group = "orders"
      query_scope      = "COLLECTION"
      fields = [
        { field_path = "status", order = "ASCENDING" },
        { field_path = "createdAt", order = "DESCENDING" },
      ]
    },
    {
      collection_group = "orders"
      query_scope      = "COLLECTION"
      fields = [
        { field_path = "symbol", order = "ASCENDING" },
        { field_path = "createdAt", order = "DESCENDING" },
      ]
    },
    {
      collection_group = "orders"
      query_scope      = "COLLECTION"
      fields = [
        { field_path = "status", order = "ASCENDING" },
        { field_path = "symbol", order = "ASCENDING" },
        { field_path = "createdAt", order = "DESCENDING" },
      ]
    },
    {
      collection_group = "audit_logs"
      query_scope      = "COLLECTION"
      fields = [
        { field_path = "trace", order = "ASCENDING" },
        { field_path = "occurredAt", order = "DESCENDING" },
      ]
    },
    {
      collection_group = "audit_logs"
      query_scope      = "COLLECTION"
      fields = [
        { field_path = "eventType", order = "ASCENDING" },
        { field_path = "occurredAt", order = "DESCENDING" },
      ]
    },
    {
      collection_group = "model_registry"
      query_scope      = "COLLECTION"
      fields = [
        { field_path = "status", order = "ASCENDING" },
        { field_path = "createdAt", order = "DESCENDING" },
      ]
    },
    {
      collection_group = "insight_records"
      query_scope      = "COLLECTION"
      fields = [
        { field_path = "theme", order = "ASCENDING" },
        { field_path = "collectedAt", order = "DESCENDING" },
      ]
    },
    {
      collection_group = "hypothesis_registry"
      query_scope      = "COLLECTION"
      fields = [
        { field_path = "status", order = "ASCENDING" },
        { field_path = "updatedAt", order = "DESCENDING" },
      ]
    },
    {
      collection_group = "failure_knowledge"
      query_scope      = "COLLECTION"
      fields = [
        { field_path = "similarityHash", order = "ASCENDING" },
        { field_path = "createdAt", order = "DESCENDING" },
      ]
    },
    {
      collection_group = "source_policies"
      query_scope      = "COLLECTION"
      fields = [
        { field_path = "sourceType", order = "ASCENDING" },
        { field_path = "enabled", order = "ASCENDING" },
        { field_path = "updatedAt", order = "DESCENDING" },
      ]
    },
    {
      collection_group = "code_reference_templates"
      query_scope      = "COLLECTION"
      fields = [
        { field_path = "scope", order = "ASCENDING" },
        { field_path = "updatedAt", order = "DESCENDING" },
      ]
    },
  ]

  ttl_fields = [
    { collection_group = "idempotency_keys", field_path = "expiresAt" },
    { collection_group = "audit_logs", field_path = "expiresAt" },
    { collection_group = "insight_records", field_path = "expiresAt" },
  ]

  depends_on = [module.project_services]
}
