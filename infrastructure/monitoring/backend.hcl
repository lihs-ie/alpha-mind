# GCS remote backend configuration for monitoring state (default: STG)
# This is the fallback config. Each environment overrides via envs/{env}/backend.hcl
# Usage: terraform init -backend-config=backend.hcl
bucket = "tfstate-alpha-mind-stg-monitoring"
prefix = "monitoring"
