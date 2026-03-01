project_id                   = "alpha-mind-stg"
region                       = "asia-northeast1"
environment                  = "stg"
alert_email_page             = "ops-page@alpha-mind.dev"
alert_email_ticket           = "ops-ticket@alpha-mind.dev"
# budget_notification_email is set via direnv (.envrc)
monthly_budget_amount        = 10000
budget_currency_code         = "JPY"
budget_threshold_percentages = [20, 50, 80, 100]
# billing_account_id is set via direnv (.envrc)
# Setup: cp .envrc.example .envrc && direnv allow
