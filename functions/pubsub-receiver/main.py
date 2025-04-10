from flask import Flask, request, jsonify
from google.cloud import pubsub_v1
import os

app = Flask(__name__)

# Initialize Pub/Sub client
publisher = pubsub_v1.PublisherClient()
topic_name = 'projects/{project_id}/topics/feedback-topic'.format(project_id=os.environ['GCP_PROJECT_ID'])

@app.route('/receiver', methods=['POST'])
def receiver():
    data = request.get_json()
    
    if 'user_id' not in data or 'message' not in data:
        return jsonify({'error': 'Invalid input'}), 400

    user_id = data['user_id']
    message = data['message']

    # Publish message to Pub/Sub
    future = publisher.publish(topic_name, data=message.encode('utf-8'), user_id=user_id.encode('utf-8'))
    future.result()  # Wait for the publish to succeed

    return jsonify({'status': 'Message published'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)