"""Verify Turnstile before reading the private resume. Never log tokens."""
import base64
import json
import os
import urllib.parse
import urllib.request


def result(status, body):
    return {"statusCode": status, "headers": {"Content-Type": "application/json", "Cache-Control": "no-store"}, "body": json.dumps(body)}


def client(service):
    import boto3
    from botocore.config import Config
    return boto3.client(service, config=Config(connect_timeout=2, read_timeout=3, retries={"max_attempts": 1}))


def verify(token):
    secret = client("ssm").get_parameter(Name=os.environ["TURNSTILE_SECRET_PARAMETER"], WithDecryption=True)["Parameter"]["Value"]
    data = urllib.parse.urlencode({"secret": secret, "response": token}).encode()
    request = urllib.request.Request("https://challenges.cloudflare.com/turnstile/v0/siteverify", data=data, method="POST")
    with urllib.request.urlopen(request, timeout=5) as response:
        return json.load(response)


def handler(event):
    if event.get("httpMethod") != "POST":
        return result(405, {"message": "Method not allowed"})
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    if headers.get("content-type", "").split(";")[0].strip().lower() != "application/json":
        return result(415, {"message": "Expected application/json"})
    raw = event.get("body") or ""
    if event.get("isBase64Encoded") or len(raw.encode()) > 4096:
        return result(400, {"message": "Invalid request"})
    try:
        payload = json.loads(raw)
        if not isinstance(payload, dict) or set(payload) != {"token"}:
            raise ValueError()
        token = payload["token"]
        if not isinstance(token, str) or not 1 <= len(token) <= 2048:
            raise ValueError()
    except (ValueError, TypeError, KeyError):
        return result(400, {"message": "Invalid request"})
    try:
        version = os.environ.get("RESUME_VERSION", "")
        domain = os.environ.get("SITE_DOMAIN", "")
        if not version or not domain:
            return result(503, {"message": "Download unavailable"})
        verified = verify(token)
        if (verified.get("success") is not True or verified.get("hostname") not in {domain, "www." + domain}
                or verified.get("action") != "resume-download"):
            return result(403, {"message": "Please verify again"})
        obj = client("s3").get_object(Bucket=os.environ["ARTIFACTS_BUCKET"], Key=f"resume/{version}/resume.pdf")
        stream = obj["Body"]
        try:
            pdf = stream.read(2_000_001)
        finally:
            stream.close()
        if len(pdf) > 2_000_000 or not pdf.startswith(b"%PDF-"):
            raise ValueError("Invalid PDF")
        return result(200, {"pdf": base64.b64encode(pdf).decode("ascii")})
    except Exception:
        # Secrets, tokens, provider responses and PDF contents must not enter logs.
        print("Resume download unavailable")
        return result(503, {"message": "Please try again"})
