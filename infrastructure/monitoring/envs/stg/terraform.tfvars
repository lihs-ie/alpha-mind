project_id                   = "alpha-mind-stg"
region                       = "asia-northeast1"
environment                  = "stg"
alert_email_page             = "ops-page@alpha-mind.dev"
alert_email_ticket           = "ops-ticket@alpha-mind.dev"
monthly_budget_amount        = 10000
budget_currency_code         = "JPY"
budget_threshold_percentages = [20, 50, 80, 100]
# billing_account_id と budget_notification_email は direnv (.envrc) 経由で注入
# Setup: cp .envrc.example .envrc && direnv allow
