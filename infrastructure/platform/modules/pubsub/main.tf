# pubsub: Pub/Sub topics, subscriptions, and DLQs per INF-004
# Naming:
#   topic:       event-{event-type-dash}-v1
#   subscription: sub-{consumer}-event-{event-type-dash}-v1
#   DLQ topic:   dlq-{consumer}-event-{event-type-dash}-v1
#   DLQ sub:     sub-dlq-{consumer}-event-{event-type-dash}-v1

locals {
  # Event wiring per INF-004 section 7.2
  # Format: event_type_dash => list of subscriber service names
  event_subscribers = {
    "market-collect-requested"      = ["data-collector", "audit-log"]
    "market-collected"              = ["feature-engineering", "audit-log"]
    "market-collect-failed"         = ["audit-log"]
    "features-generated"            = ["signal-generator", "audit-log"]
    "features-generation-failed"    = ["audit-log"]
    "signal-generated"              = ["portfolio-planner", "audit-log"]
    "signal-generation-failed"      = ["audit-log"]
    "orders-proposed"               = ["risk-guard", "audit-log"]
    "orders-proposal-failed"        = ["audit-log"]
    "orders-approved"               = ["execution", "audit-log"]
    "orders-rejected"               = ["audit-log"]
    "orders-executed"               = ["audit-log"]
    "orders-execution-failed"       = ["audit-log"]
    "operation-kill-switch-changed" = ["risk-guard", "audit-log"]
    "insight-collect-requested"     = ["insight-collector", "audit-log"]
    "insight-collected"             = ["agent-orchestrator", "audit-log"]
    "insight-collect-failed"        = ["audit-log"]
    "hypothesis-retest-requested"   = ["agent-orchestrator", "audit-log"]
    "hypothesis-proposed"           = ["hypothesis-lab", "audit-log"]
    "hypothesis-proposal-failed"    = ["audit-log"]
    "hypothesis-demo-completed"     = ["hypothesis-lab", "audit-log"]
    "hypothesis-backtested"         = ["audit-log"]
    "hypothesis-promoted"           = ["audit-log"]
    "hypothesis-rejected"           = ["audit-log"]
  }

  # Topics that exist per INF-004 but have no active subscribers yet
  # audit-recorded: subscriber "audit-view" is marked as optional in INF-004
  # and no SA exists for audit-view. Topic is created for publisher readiness.
  subscriber_less_topics = toset([
    "audit-recorded",
  ])

  # Flatten: one entry per (event_type, subscriber) pair
  subscriptions = flatten([
    for event_type, subscribers in local.event_subscribers : [
      for subscriber in subscribers : {
        event_type     = event_type
        subscriber     = subscriber
        topic_name     = "event-${event_type}-v1"
        sub_name       = "sub-${subscriber}-event-${event_type}-v1"
        dlq_topic_name = "dlq-${subscriber}-event-${event_type}-v1"
        dlq_sub_name   = "sub-dlq-${subscriber}-event-${event_type}-v1"
        key            = "${subscriber}__${event_type}"
      }
    ]
  ])

  subscriptions_map = { for s in local.subscriptions : s.key => s }
}

# All event topic names (with and without subscribers)
locals {
  all_topic_names = toset(concat(
    keys(local.event_subscribers),
    tolist(local.subscriber_less_topics),
  ))
}

# Main event topics
resource "google_pubsub_topic" "events" {
  for_each = local.all_topic_names

  project = var.project_id
  name    = "event-${each.key}-v1"

  message_retention_duration = "604800s" # 7 days
}

# DLQ topics (one per subscription)
resource "google_pubsub_topic" "dlq" {
  for_each = local.subscriptions_map

  project = var.project_id
  name    = each.value.dlq_topic_name

  message_retention_duration = "604800s" # 7 days
}

# Subscriptions with retry and DLQ policy per INF-004 section 7.3
resource "google_pubsub_subscription" "subscriptions" {
  for_each = local.subscriptions_map

  project = var.project_id
  name    = each.value.sub_name
  topic   = google_pubsub_topic.events[each.value.event_type].id

  ack_deadline_seconds       = 60
  message_retention_duration = "604800s" # 7 days
  enable_message_ordering    = false

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq[each.key].id
    max_delivery_attempts = 5
  }
}

# Pub/Sub サービスエージェントが DLQ トピックにメッセージを転送するための IAM 付与
data "google_project" "current" {
  project_id = var.project_id
}

resource "google_pubsub_topic_iam_member" "dlq_publisher" {
  for_each = local.subscriptions_map

  project = var.project_id
  topic   = google_pubsub_topic.dlq[each.key].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# DLQ subscriptions (for manual inspection and replay)
resource "google_pubsub_subscription" "dlq_subscriptions" {
  for_each = local.subscriptions_map

  project = var.project_id
  name    = each.value.dlq_sub_name
  topic   = google_pubsub_topic.dlq[each.key].id

  ack_deadline_seconds       = 60
  message_retention_duration = "604800s" # 7 days
}
