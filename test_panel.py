#!/usr/bin/env python3
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PANEL = (ROOT / "Panel.qml").read_text()


def block_after(marker: str) -> str:
    idx = PANEL.find(marker)
    if idx < 0:
        raise AssertionError(f"missing {marker!r}")
    return PANEL[idx : idx + 400]


class PanelIdlePollTests(unittest.TestCase):
    def test_layout_poll_timer_runs_only_while_open(self):
        timer = block_after("id: layoutPollTimer")
        self.assertIn("running: root.opened", timer)
        self.assertIn("triggeredOnStart: true", timer)
        self.assertNotIn("running: true", timer)

    def test_poll_layout_bails_when_closed(self):
        fn = block_after("function pollLayout()")
        self.assertRegex(fn, r"if\s*\(\s*!root\.opened\s*\)")

    def test_pending_poll_does_not_restart_when_closed(self):
        self.assertIn("if (root.opened) Qt.callLater(root.pollLayout)", PANEL)

    def test_no_unconditional_120ms_poll(self):
        timers = re.findall(r"Timer\s*\{[^}]+\}", PANEL, flags=re.S)
        for timer in timers:
            if "interval: 120" not in timer:
                continue
            self.assertIn("running: root.opened", timer)
            self.assertNotRegex(timer, r"running:\s*true")


if __name__ == "__main__":
    unittest.main()
