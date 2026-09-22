import importlib.util
import json
import pathlib
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("handler", pathlib.Path(__file__).parents[2] / "backend/recruiter/handler.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.db = Mock()
        module._table = self.db
        self.event = {"httpMethod": "POST", "headers": {"Content-Type": "application/json", "Idempotency-Key": "f21fa093-fc4b-4825-8e8b-67343c8bfc15"}, "body": json.dumps({"recruiter": True, "companyName": "  Example   Company "})}

    def test_success_minimizes_data_and_sets_ttl(self):
        with patch.object(module.time, "time", return_value=1000):
            result = module.handler(self.event, None)
        self.assertEqual(201, result["statusCode"])
        item = self.db.put_item.call_args.kwargs["Item"]
        self.assertEqual("Example Company", item["companyName"])
        self.assertEqual(1000 + 30 * 86400, item["expiresAt"])
        self.assertEqual({"requestId", "companyName", "createdAt", "expiresAt", "source", "payloadHash"}, set(item))

    def test_invalid_payloads_never_write(self):
        for payload in [{"recruiter": False, "companyName": "ACME"}, {"recruiter": 1, "companyName": "ACME"}, {"recruiter": True, "companyName": " "}, {"recruiter": True, "companyName": "x" * 121}, {"recruiter": True, "companyName": "ACME", "email": "x"}, [], None]:
            with self.subTest(payload=payload):
                self.event["body"] = json.dumps(payload)
                self.assertEqual(400, module.handler(self.event, None)["statusCode"])
        self.db.put_item.assert_not_called()

    def test_retry_is_idempotent(self):
        err = Exception()
        err.response = {"Error": {"Code": "ConditionalCheckFailedException"}, "Item": {"payloadHash": {"S": module.hashlib.sha256(b"Example Company").hexdigest()}}}
        self.db.put_item.side_effect = err
        self.assertEqual(200, module.handler(self.event, None)["statusCode"])

    def test_changed_retry_conflicts(self):
        err = Exception()
        err.response = {"Error": {"Code": "ConditionalCheckFailedException"}, "Item": {"payloadHash": {"S": "other"}}}
        self.db.put_item.side_effect = err
        self.assertEqual(409, module.handler(self.event, None)["statusCode"])

    def test_database_failure_is_retryable(self):
        self.db.put_item.side_effect = RuntimeError("private details")
        result = module.handler(self.event, None)
        self.assertEqual(503, result["statusCode"])
        self.assertNotIn("private details", result["body"])

    def test_invalid_method_type_id_and_json(self):
        for change, expected in [({"httpMethod": "GET"}, 405), ({"body": "{"}, 400), ({"body": "x" * 1025}, 400), ({"headers": {"Content-Type": "text/plain"}}, 415), ({"headers": {"Content-Type": "application/json"}}, 400)]:
            self.assertEqual(expected, module.handler({**self.event, **change}, None)["statusCode"])
        self.db.put_item.assert_not_called()
