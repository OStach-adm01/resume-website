#!/usr/bin/env python3
"""Store the secret without exposing it in shell history or process arguments."""
import getpass
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def save_secret(secret, validate_only=False):
    # CLI v2 may read file:// input more than once; a pipe is not seekable.
    # TemporaryDirectory is owner-only (0700); remove the payload on every exit.
    with tempfile.TemporaryDirectory(prefix="resume-turnstile-") as directory:
        payload = Path(directory) / "parameter.json"
        with payload.open("x", encoding="utf-8") as stream:
            payload.chmod(0o600)
            json.dump({"Name": "/resume-website/turnstile-secret", "Type": "SecureString", "KeyId": "alias/aws/ssm", "Value": secret, "Overwrite": True}, stream)
        command = ["aws", "ssm", "put-parameter", "--profile", "resume-terraform", "--region", "eu-central-1", "--cli-input-json", f"file://{payload}", "--no-cli-pager"]
        if validate_only:
            command += ["--generate-cli-skeleton", "output"]
        return subprocess.run(command, text=True, capture_output=True, check=False)


def safe_error(stderr):
    # Never echo raw stderr: parser errors can contain the submitted JSON.
    match = re.search(r"An error occurred \(([A-Za-z0-9_.-]{1,80})\)", stderr)
    return match.group(1) if match else "UnclassifiedCliError"

if __name__ == "__main__":
    identity = subprocess.run(
        ["aws", "sts", "get-caller-identity", "--profile", "resume-terraform", "--region", "eu-central-1", "--output", "json", "--no-cli-pager"],
        text=True, capture_output=True, check=False,
    )
    if identity.returncode:
        sys.exit("AWS authentication failed; refresh resume-login before retrying.")
    caller = json.loads(identity.stdout)
    if caller.get("Account") != "108327566685" or caller.get("Arn", "").endswith(":root"):
        sys.exit("Unexpected AWS identity; nothing changed.")
    secret = getpass.getpass("Turnstile Secret Key (hidden): ").strip()
    if not secret:
        sys.exit("No secret supplied; nothing changed.")
    result = save_secret(secret)
    if result.returncode:
        sys.exit(f"Secret was not saved ({safe_error(result.stderr)}; CLI exit {result.returncode}). No secret was printed.")
    print("Turnstile secret saved as an encrypted SSM parameter. Value not displayed.")
