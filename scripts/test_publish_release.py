"""Exercise the release publisher without AWS credentials or network calls."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().with_name("publish-release.sh")
SHA = "a" * 40
DIGEST = "sha256:" + "b" * 64

AWS_STUB = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open("calls.jsonl", "a") as log:
    log.write(json.dumps(args) + "\n")
if args[:2] == ["s3api", "list-objects-v2"]:
    if os.environ["MODE"] == "denied":
        sys.exit(1)
    print(os.environ["LISTING"])
elif args[:2] == ["s3", "cp"] and args[2].endswith("/manifest.json"):
    Path(args[3]).write_text(json.dumps({"imageDigest": os.environ["IMAGE_DIGEST"], "resumeVersion": ""}))
'''
HELM_STUB = r'''#!/usr/bin/env python3
from pathlib import Path
Path(".artifacts/resume-0.1.0.tgz").write_bytes(b"test chart")
'''


class PublishReleaseTests(unittest.TestCase):
    def run_publisher(self, listing, mode="ok"):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "bin").mkdir()
            (root / "dist/_astro").mkdir(parents=True)
            (root / "dist/index.html").write_text("test site")
            for name, content in (("aws", AWS_STUB), ("helm", HELM_STUB)):
                path = root / "bin" / name
                path.write_text(content)
                path.chmod(0o755)
            env = {**os.environ, "PATH": f"{root / 'bin'}:{os.environ['PATH']}",
                   "RELEASE_SHA": SHA, "IMAGE_DIGEST": DIGEST,
                   "RESUME_VERSION": "", "ARTIFACTS_BUCKET": "test-bucket",
                   "LISTING": json.dumps(listing), "MODE": mode}
            result = subprocess.run(["bash", str(SCRIPT)], cwd=root, env=env,
                                    capture_output=True, text=True)
            calls = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
            return result, calls

    def test_first_release_without_keycount_publishes_manifest_last(self):
        result, calls = self.run_publisher({"Prefix": f"releases/{SHA}/manifest.json"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[-1][:2], ["s3api", "put-object"])
        self.assertIn("--if-none-match", calls[-1])
        self.assertFalse(any(call[:2] == ["s3", "cp"] and call[2].endswith("/manifest.json") for call in calls))

    def test_existing_release_is_reused_without_upload(self):
        result, calls = self.run_publisher({"Contents": [{"Key": f"releases/{SHA}/manifest.json"}]})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Reusing", result.stdout)
        self.assertEqual(len(calls), 2)

    def test_similar_prefix_is_not_a_completed_release(self):
        result, calls = self.run_publisher({"Contents": [{"Key": f"releases/{SHA}/manifest.json.backup"}]})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[-1][:2], ["s3api", "put-object"])

    def test_list_failure_stops_before_upload(self):
        result, calls = self.run_publisher({}, mode="denied")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)


if __name__ == "__main__":
    unittest.main()
