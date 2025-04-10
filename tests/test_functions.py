import json
import unittest
from unittest.mock import patch
from functions.pubsub_receiver.main import publish_message
from functions.pubsub_positive_analyzer.main import analyze_positive_sentiment
from functions.pubsub_negative_analyzer.main import analyze_negative_sentiment

class TestSentimentAnalysisFunctions(unittest.TestCase):

    @patch('functions.pubsub_receiver.main.publish_to_pubsub')
    def test_publish_message(self, mock_publish):
        user_id = "test@example.com"
        message = "I love this!"
        response = publish_message(user_id, message)
        self.assertTrue(mock_publish.called)
        self.assertEqual(response, {"status": "Message published"})

    @patch('functions.pubsub_positive_analyzer.main.send_slack_alert')
    def test_analyze_positive_sentiment(self, mock_send_alert):
        message = {"user_id": "test@example.com", "message": "I love this!"}
        score = analyze_positive_sentiment(message)
        self.assertGreater(score, 0.25)
        self.assertTrue(mock_send_alert.called)

    @patch('functions.pubsub_negative_analyzer.main.send_slack_alert')
    def test_analyze_negative_sentiment(self, mock_send_alert):
        message = {"user_id": "test@example.com", "message": "This isn’t working."}
        score = analyze_negative_sentiment(message)
        self.assertLess(score, -0.25)
        self.assertTrue(mock_send_alert.called)

if __name__ == '__main__':
    unittest.main()