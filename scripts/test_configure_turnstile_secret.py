"""Test secret transport with fake values and no AWS writes."""
import importlib.util
import json
from pathlib import Path
import stat
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("configure", Path(__file__).with_name("configure-turnstile-secret.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SecretTransportTests(unittest.TestCase):
    def test_private_seekable_payload_is_removed(self):
        paths = []

        def invoke(command, **kwargs):
            self.assertNotIn("fake-secret", str(command))
            self.assertNotIn("input", kwargs)
            payload = Path(command[command.index("--cli-input-json") + 1].removeprefix("file://"))
            paths.append(payload)
            self.assertEqual(0o600, stat.S_IMODE(payload.stat().st_mode))
            self.assertEqual(0o700, stat.S_IMODE(payload.parent.stat().st_mode))
            self.assertEqual("fake-secret", json.loads(payload.read_text())["Value"])
            self.assertEqual(payload.read_text(), payload.read_text())
            return Mock(returncode=0)

        with patch.object(module.subprocess, "run", side_effect=invoke):
            self.assertEqual(0, module.save_secret("fake-secret").returncode)
        self.assertFalse(paths[0].parent.exists())

    def test_cleanup_on_subprocess_exception(self):
        paths = []

        def fail(command, **kwargs):
            paths.append(Path(command[command.index("--cli-input-json") + 1].removeprefix("file://")))
            raise OSError("test failure")

        with patch.object(module.subprocess, "run", side_effect=fail):
            with self.assertRaises(OSError):
                module.save_secret("fake-secret")
        self.assertFalse(paths[0].parent.exists())

    def test_errors_do_not_echo_payloads(self):
        self.assertEqual("AccessDeniedException", module.safe_error("An error occurred (AccessDeniedException): fake-secret"))
        self.assertEqual("UnclassifiedCliError", module.safe_error('Invalid JSON: {"Value":"fake-secret"}'))
