from google.cloud import pubsub_v1
from google.cloud import language_v1
import json
import os
import requests

def analyze_sentiment(event, context):
    # Decode the Pub/Sub message
    pubsub_message = base64.b64decode(event['data']).decode('utf-8')
    message_data = json.loads(pubsub_message)

    user_id = message_data['user_id']
    message = message_data['message']

    # Analyze sentiment
    client = language_v1.LanguageServiceClient()
    document = language_v1.Document(content=message, type_=language_v1.Document.Type.PLAIN_TEXT)
    sentiment = client.analyze_sentiment(request={'document': document}).document_sentiment

    # Check sentiment score
    if sentiment.score < -0.25:
        send_slack_alert(user_id, message, sentiment.score)

def send_slack_alert(user_id, message, score):
    slack_token = os.environ.get('SLACK_TOKEN')
    slack_channel = '#support'
    slack_message = {
        'channel': slack_channel,
        'text': f"Negative feedback from {user_id}: {message} (Score: {score})"
    }
    headers = {
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {slack_token}'
    }
    requests.post('https://slack.com/api/chat.postMessage', headers=headers, json=slack_message)