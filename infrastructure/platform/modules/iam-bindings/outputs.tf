output "common_binding_keys" {
  description = "Keys of common IAM bindings applied"
  value       = keys(google_project_iam_member.common)
}

output "additional_binding_keys" {
  description = "Keys of additional IAM bindings applied"
  value       = keys(google_project_iam_member.additional)
}
