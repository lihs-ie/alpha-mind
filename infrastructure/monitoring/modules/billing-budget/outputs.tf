output "budget_name" {
  description = "The resource name of the billing budget"
  value       = google_billing_budget.monthly.name
}

output "budget_display_name" {
  description = "The display name of the billing budget"
  value       = google_billing_budget.monthly.display_name
}
