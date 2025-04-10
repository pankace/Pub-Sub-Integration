output "pubsub_topic_name" {
  value = google_pubsub_topic.feedback_topic.name
}

output "positive_subscription_name" {
  value = google_pubsub_subscription.positive_sub.name
}

output "negative_subscription_name" {
  value = google_pubsub_subscription.negative_sub.name
}