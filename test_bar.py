#!/usr/bin/env python3
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BAR = (ROOT / "BarWidget.qml").read_text()


class BarWorkspaceListTests(unittest.TestCase):
    def test_syncs_from_hyprland_workspace_model(self):
        self.assertIn("target: Hyprland.workspaces", BAR)
        self.assertIn("function onValuesChanged()", BAR)
        self.assertIn("root.syncDisplayedIds()", BAR)

    def test_no_forever_workspace_poll(self):
        timers = re.findall(r"Timer\s*\{[^}]+\}", BAR, flags=re.S)
        for timer in timers:
            self.assertNotRegex(timer, r"running:\s*true")
            self.assertNotIn("syncDisplayedIds", timer)


if __name__ == "__main__":
    unittest.main()
