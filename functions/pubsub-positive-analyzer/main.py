from google.cloud import pubsub_v1
from google.cloud import language_v1
import os
import json
import requests

def analyze_sentiment(event, context):
    # Decode the Pub/Sub message
    pubsub_message = base64.b64decode(event['data']).decode('utf-8')
    message_data = json.loads(pubsub_message)

    user_id = message_data['user_id']
    message = message_data['message']

    # Initialize the Natural Language API client
    client = language_v1.LanguageServiceClient()

    # Analyze the sentiment of the message
    document = language_v1.Document(content=message, type_=language_v1.Document.Type.PLAIN_TEXT)
    sentiment = client.analyze_sentiment(request={'document': document}).document_sentiment

    # Check if the sentiment score is greater than 0.25
    if sentiment.score > 0.25:
        send_slack_alert(user_id, message, 'followup')

def send_slack_alert(user_id, message, channel):
    slack_token = os.environ.get('SLACK_TOKEN')
    slack_url = f'https://slack.com/api/chat.postMessage'
    
    headers = {
        'Authorization': f'Bearer {slack_token}',
        'Content-Type': 'application/json'
    }

    payload = {
        'channel': f'#{channel}',
        'text': f'User {user_id} sent a positive message: "{message}"'
    }

    response = requests.post(slack_url, headers=headers, json=payload)
    response.raise_for_status()