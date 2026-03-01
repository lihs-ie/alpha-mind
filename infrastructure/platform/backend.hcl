# GCS remote backend configuration for platform state (default: STG)
# This is the fallback config. Each environment overrides via envs/{env}/backend.hcl
# Usage: terraform init -backend-config=backend.hcl
bucket = "tfstate-alpha-mind-stg-platform"
prefix = "platform"
