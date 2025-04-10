# Provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
}

# Pub/Sub resources
resource "google_pubsub_topic" "feedback_topic" {
  name = "feedback-topic"
}

resource "google_pubsub_subscription" "positive_sub" {
  name  = "positive-sub"
  topic = google_pubsub_topic.feedback_topic.name
}

resource "google_pubsub_subscription" "negative_sub" {
  name  = "negative-sub"
  topic = google_pubsub_topic.feedback_topic.name
}

# BigQuery resources
resource "google_bigquery_dataset" "feedback_dataset" {
  dataset_id = "feedback_dataset"
  location   = "US"
}

resource "google_bigquery_table" "feedback_table" {
  dataset_id = google_bigquery_dataset.feedback_dataset.dataset_id
  table_id   = "feedback_table"

  schema = jsonencode([
    {
      name = "user_id"
      type = "STRING"
    },
    {
      name = "message"
      type = "STRING"
    }
  ])
}

# BigQuery subscription to Pub/Sub for message archiving (optional)
resource "google_pubsub_subscription" "bigquery_subscription" {
  name  = "bigquery-subscription"
  topic = google_pubsub_topic.feedback_topic.name

  bigquery_config {
    table            = "${google_bigquery_table.feedback_table.project}.${google_bigquery_dataset.feedback_dataset.dataset_id}.${google_bigquery_table.feedback_table.table_id}"
    use_topic_schema = false
    write_metadata   = true
  }
}

# Secret Manager for Slack token
resource "google_secret_manager_secret" "slack_token" {
  secret_id = "slacktoken"
  
  replication {
    automatic = true
  }
}

# Note: You should set the actual secret value separately using the command:
# gcloud secrets versions add slacktoken --data-file=/path/to/token.txt

# Service accounts for Cloud Functions
resource "google_service_account" "function_service_account" {
  account_id   = "sentiment-functions-sa"
  display_name = "Sentiment Analysis Functions Service Account"
}

# IAM permissions
resource "google_project_iam_binding" "pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  
  members = [
    "serviceAccount:${google_service_account.function_service_account.email}",
  ]
}

resource "google_project_iam_binding" "pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  
  members = [
    "serviceAccount:${google_service_account.function_service_account.email}",
  ]
}

resource "google_secret_manager_secret_iam_binding" "secret_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.slack_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  
  members = [
    "serviceAccount:${google_service_account.function_service_account.email}",
  ]
}

# Cloud Functions
resource "google_cloudfunctions_function" "receiver_function" {
  name        = "pubsub-receiver"
  description = "Receives feedback and publishes to Pub/Sub"
  runtime     = "python39"
  
  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.function_bucket.name
  source_archive_object = google_storage_bucket_object.receiver_archive.name
  trigger_http          = true
  entry_point           = "receive_message"
  service_account_email = google_service_account.function_service_account.email
  
  environment_variables = {
    PUBSUB_TOPIC = google_pubsub_topic.feedback_topic.name
  }
}

resource "google_cloudfunctions_function" "positive_analyzer" {
  name        = "pubsub-positive-analyzer"
  description = "Analyzes positive sentiment and sends Slack alerts"
  runtime     = "python39"
  
  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.function_bucket.name
  source_archive_object = google_storage_bucket_object.positive_analyzer_archive.name
  entry_point           = "analyze_sentiment"
  service_account_email = google_service_account.function_service_account.email
  
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.feedback_topic.name
  }
  
  secret_environment_variables {
    key     = "SLACK_TOKEN"
    secret  = google_secret_manager_secret.slack_token.secret_id
    version = "latest"
  }
  
  environment_variables = {
    SLACK_CHANNEL = "followup"
    SENTIMENT_THRESHOLD = "0.25"
  }
}

resource "google_cloudfunctions_function" "negative_analyzer" {
  name        = "pubsub-negative-analyzer"
  description = "Analyzes negative sentiment and sends Slack alerts"
  runtime     = "python39"
  
  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.function_bucket.name
  source_archive_object = google_storage_bucket_object.negative_analyzer_archive.name
  entry_point           = "analyze_sentiment"
  service_account_email = google_service_account.function_service_account.email
  
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.feedback_topic.name
  }
  
  secret_environment_variables {
    key     = "SLACK_TOKEN"
    secret  = google_secret_manager_secret.slack_token.secret_id
    version = "latest"
  }
  
  environment_variables = {
    SLACK_CHANNEL = "support"
    SENTIMENT_THRESHOLD = "-0.25"
  }
}

# Storage for Cloud Functions source code
resource "google_storage_bucket" "function_bucket" {
  name     = "${var.project_id}-function-source"
  location = "US"
}

# Zip and upload function source code
data "archive_file" "receiver_source" {
  type        = "zip"
  source_dir  = "${path.module}/../functions/pubsub-receiver"
  output_path = "${path.module}/tmp/receiver.zip"
}

resource "google_storage_bucket_object" "receiver_archive" {
  name   = "receiver-${data.archive_file.receiver_source.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.receiver_source.output_path
}

data "archive_file" "positive_analyzer_source" {
  type        = "zip"
  source_dir  = "${path.module}/../functions/pubsub-positive-analyzer"
  output_path = "${path.module}/tmp/positive-analyzer.zip"
}

resource "google_storage_bucket_object" "positive_analyzer_archive" {
  name   = "positive-analyzer-${data.archive_file.positive_analyzer_source.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.positive_analyzer_source.output_path
}

data "archive_file" "negative_analyzer_source" {
  type        = "zip"
  source_dir  = "${path.module}/../functions/pubsub-negative-analyzer"
  output_path = "${path.module}/tmp/negative-analyzer.zip"
}

resource "google_storage_bucket_object" "negative_analyzer_archive" {
  name   = "negative-analyzer-${data.archive_file.negative_analyzer_source.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.negative_analyzer_source.output_path
}

# IAM for Cloud Function invoker
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.receiver_function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"  # This allows public access - restrict in production
}