"""Recruiter-interest collector. Never log submitted data."""
import hashlib
import json
import os
import re
import time
import unicodedata
import uuid

_table = None


def table():
    global _table
    if _table is None:
        import boto3
        _table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
    return _table


def response(status, message):
    return {"statusCode": status, "headers": {"Content-Type": "application/json", "Cache-Control": "no-store"}, "body": json.dumps({"message": message})}


def handler(event, _context):
    if event.get("httpMethod") != "POST":
        return response(405, "Method not allowed")
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    if headers.get("content-type", "").split(";")[0].strip().lower() != "application/json":
        return response(415, "Expected application/json")
    raw = event.get("body") or ""
    if event.get("isBase64Encoded") or len(raw.encode("utf-8")) > 1024:
        return response(400, "Invalid request")
    try:
        payload = json.loads(raw)
        if not isinstance(payload, dict) or set(payload) != {"recruiter", "companyName"}:
            raise ValueError()
        if payload["recruiter"] is not True or not isinstance(payload["companyName"], str):
            raise ValueError()
        company = " ".join(unicodedata.normalize("NFKC", payload["companyName"]).split())
        if not 2 <= len(company) <= 120 or re.search(r"[\x00-\x1f\x7f]", company):
            raise ValueError()
        request_id = str(uuid.UUID(headers.get("idempotency-key", "")))
    except (ValueError, TypeError, KeyError):
        return response(400, "Invalid request")
    digest = hashlib.sha256(company.encode("utf-8")).hexdigest()
    now = int(time.time())
    try:
        table().put_item(Item={"requestId": request_id, "companyName": company, "payloadHash": digest, "createdAt": now, "expiresAt": now + 30 * 86400, "source": "resume-download"}, ConditionExpression="attribute_not_exists(requestId)", ReturnValuesOnConditionCheckFailure="ALL_OLD")
    except Exception as exc:
        detail = getattr(exc, "response", {})
        if detail.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            old = detail.get("Item", {}).get("payloadHash", {})
            if old == {"S": digest} or old == digest:
                return response(200, "Already recorded")
            return response(409, "Request identifier already used")
        print("Recruiter record write failed")
        return response(503, "Please try again")
    return response(201, "Recorded")
