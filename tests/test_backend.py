from __future__ import annotations

import sys
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from codex_proxy_assistant.backend import PowerShellBackend  # noqa: E402


class BackendSmokeTests(unittest.TestCase):
    def test_detection_returns_structured_state(self) -> None:
        report = PowerShellBackend().detect()
        self.assertIn("installations", report)
        self.assertIn("proxy", report)
        self.assertIn("config", report)
        self.assertTrue(str(report["config"]["path"]).lower().endswith("config.toml"))


if __name__ == "__main__":
    unittest.main()
