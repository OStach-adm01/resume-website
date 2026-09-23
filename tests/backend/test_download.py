import base64
import importlib.util
import io
import json
import os
import pathlib
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("download", pathlib.Path(__file__).parents[2] / "backend/recruiter/download.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {"RESUME_VERSION": "v1", "SITE_DOMAIN": "example.com", "ARTIFACTS_BUCKET": "private", "TURNSTILE_SECRET_PARAMETER": "/site/secret"})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.event = {"httpMethod": "POST", "headers": {"Content-Type": "application/json"}, "body": json.dumps({"token": "valid-token"})}
        self.verified = {"success": True, "hostname": "example.com", "action": "resume-download"}

    def test_valid_token_reads_only_configured_pdf(self):
        s3 = Mock()
        s3.get_object.return_value = {"Body": io.BytesIO(b"%PDF-1.4\n%%EOF")}
        with patch.object(module, "verify", return_value=self.verified), patch.object(module, "client", return_value=s3):
            response = module.handler(self.event)
        self.assertEqual(200, response["statusCode"])
        self.assertEqual("no-store", response["headers"]["Cache-Control"])
        self.assertTrue(base64.b64decode(json.loads(response["body"])["pdf"]).startswith(b"%PDF-"))
        s3.get_object.assert_called_once_with(Bucket="private", Key="resume/v1/resume.pdf")

    def test_failed_expired_wrong_host_or_action_never_reads_pdf(self):
        for result in [{"success": False, "error-codes": ["timeout-or-duplicate"]}, {**self.verified, "hostname": "evil.example"}, {**self.verified, "action": "other"}, {}]:
            with self.subTest(result=result), patch.object(module, "verify", return_value=result), patch.object(module, "client") as client:
                self.assertEqual(403, module.handler(self.event)["statusCode"])
                client.assert_not_called()

    def test_invalid_requests_never_verify(self):
        for payload in [{}, {"token": ""}, {"token": "x" * 2049}, {"token": "x", "version": "other"}, [], None, {"token": 1}]:
            with self.subTest(payload=payload), patch.object(module, "verify") as verify:
                self.assertEqual(400, module.handler({**self.event, "body": json.dumps(payload)})["statusCode"])
                verify.assert_not_called()

    def test_failures_are_closed_and_redacted(self):
        with patch.object(module, "verify", side_effect=RuntimeError("private-secret")), patch.object(module, "client") as client:
            response = module.handler(self.event)
            self.assertEqual(503, response["statusCode"])
            self.assertNotIn("private-secret", response["body"])
            client.assert_not_called()
        with patch.dict(os.environ, {"RESUME_VERSION": ""}), patch.object(module, "verify") as verify:
            self.assertEqual(503, module.handler(self.event)["statusCode"])
            verify.assert_not_called()

    def test_method_content_type_and_size(self):
        for change, code in [({"httpMethod": "GET"}, 405), ({"headers": {}}, 415), ({"isBase64Encoded": True}, 400), ({"body": "x" * 4097}, 400), ({"body": "{"}, 400)]:
            self.assertEqual(code, module.handler({**self.event, **change})["statusCode"])

    def test_siteverify_posts_secret_without_forwarding_personal_data(self):
        ssm = Mock()
        ssm.get_parameter.return_value = {"Parameter": {"Value": "private-secret"}}
        with patch.object(module, "client", return_value=ssm), patch.object(module.urllib.request, "urlopen") as request:
            request.return_value.__enter__.return_value = io.StringIO(json.dumps(self.verified))
            self.assertEqual(self.verified, module.verify("test-token"))
        ssm.get_parameter.assert_called_once_with(Name="/site/secret", WithDecryption=True)
        sent = request.call_args.args[0]
        self.assertEqual("https://challenges.cloudflare.com/turnstile/v0/siteverify", sent.full_url)
        self.assertEqual("POST", sent.method)
        self.assertEqual({"secret": ["private-secret"], "response": ["test-token"]}, module.urllib.parse.parse_qs(sent.data.decode()))

    def test_bad_pdf_fails_closed(self):
        for pdf in [b"not a PDF", b"%PDF-" + b"x" * 2_000_000]:
            s3 = Mock()
            s3.get_object.return_value = {"Body": io.BytesIO(pdf)}
            with patch.object(module, "verify", return_value=self.verified), patch.object(module, "client", return_value=s3):
                self.assertEqual(503, module.handler(self.event)["statusCode"])
