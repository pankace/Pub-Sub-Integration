import os
import json
import base64
import functions_framework
from flask import jsonify
from google.cloud import pubsub_v1

@functions_framework.http
def receive_message(request):
    """HTTP Cloud Function that receives feedback messages.
    Args:
        request (flask.Request): The request object.
        <https://flask.palletsprojects.com/en/1.1.x/api/#incoming-request-data>
    Returns:
        The response text, or any set of values that can be turned into a
        Response object using `make_response`
        <https://flask.palletsprojects.com/en/1.1.x/api/#flask.make_response>.
    """
    try:
        request_json = request.get_json(silent=True)
        
        if not request_json:
            return jsonify({'error': 'No JSON data provided'}), 400
        
        user_id = request_json.get('user_id')
        message = request_json.get('message')
        
        if not user_id or not message:
            return jsonify({'error': 'Missing required fields: user_id or message'}), 400
        
        result = publish_to_topic(user_id, message)
        return jsonify({'success': True, 'result': result})
    
    except Exception as e:
        return jsonify({'error': f'Error processing request: {str(e)}'}), 500

def publish_to_topic(user_id, message):
    """Publishes a message to the Pub/Sub topic."""
    publisher = pubsub_v1.PublisherClient()
    topic_name = os.environ.get('PUBSUB_TOPIC', 'feedback-topic')
    project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
    
    topic_path = publisher.topic_path(project_id, topic_name)
    
    data = {
        'user_id': user_id,
        'message': message
    }
    
    data_bytes = json.dumps(data).encode('utf-8')
    
    try:
        future = publisher.publish(topic_path, data=data_bytes)
        message_id = future.result()
        return f"Message published with ID: {message_id}"
    except Exception as e:
        return f"Error publishing message: {e}", 500