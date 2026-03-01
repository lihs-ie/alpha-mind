output "topic_ids" {
  description = "Map of event type dash to topic ID"
  value       = { for k, v in google_pubsub_topic.events : k => v.id }
}

output "subscription_ids" {
  description = "Map of subscription key to subscription ID"
  value       = { for k, v in google_pubsub_subscription.subscriptions : k => v.id }
}

output "dlq_topic_ids" {
  description = "Map of subscription key to DLQ topic ID"
  value       = { for k, v in google_pubsub_topic.dlq : k => v.id }
}
