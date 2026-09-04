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
    return PANEL[idx : idx + 900]


class PanelIdlePollTests(unittest.TestCase):
    def test_no_layout_subprocess_poll(self):
        self.assertNotIn("layoutProc", PANEL)
        self.assertNotIn('"hyprctl", "-j", "clients"', PANEL)
        poll = block_after("function pollGeometry()")
        self.assertNotIn("python3", poll)
        self.assertNotIn("hyprctl", poll)

    def test_no_120ms_timer(self):
        timers = re.findall(r"Timer\s*\{[^}]+\}", PANEL, flags=re.S)
        for timer in timers:
            self.assertNotIn("interval: 120", timer)

    def test_geometry_poll_runs_only_while_closed(self):
        timer = block_after("id: geometryPollTimer")
        self.assertIn("running: !root.opened", timer)
        self.assertIn("triggeredOnStart: true", timer)
        self.assertIn("root.pollGeometry()", timer)
        self.assertNotIn("running: true", timer)

    def test_geometry_poll_uses_in_process_toplevels(self):
        self.assertIn("Hyprland.refreshToplevels()", PANEL)
        fingerprint = block_after("function layoutFingerprint()")
        self.assertIn("Hyprland.toplevels.values", fingerprint)
        self.assertIn("lastIpcObject", fingerprint)
        self.assertIn("ipc.at", fingerprint)
        self.assertIn("ipc.size", fingerprint)

    def test_geometry_poll_skips_while_overlay_visible(self):
        fn = block_after("function pollGeometry()")
        self.assertIn("root.opened", fn)
        self.assertIn("overlayOnScreen()", fn)

    def test_layout_events_still_schedule_refresh(self):
        self.assertIn("function isLayoutEvent(name)", PANEL)
        connections = block_after("function onRawEvent(event)")
        self.assertIn("root.isLayoutEvent(event.name)", connections)
        self.assertIn("root.scheduleRefresh()", connections)

    def test_closing_preview_still_recaptures(self):
        fn = block_after("onOpenedChanged:")
        self.assertIn("root.scheduleRefresh()", fn)


class PanelOverlayCaptureTests(unittest.TestCase):
    def test_hover_swap_does_not_recapture(self):
        fn = block_after("function showWorkspace(")
        self.assertIn("root.setShot(workspaceId)", fn)
        self.assertNotIn("captureWorkspace", fn)

    def test_capture_skips_while_overlay_is_on_screen(self):
        fn = block_after("function captureWorkspace(")
        self.assertIn("overlayOnScreen()", fn)
        self.assertIn("if (root.overlayOnScreen()) return", fn)

    def test_opening_preview_aborts_in_flight_capture(self):
        fn = block_after("onOpenedChanged:")
        self.assertIn("root.abortCapture()", fn)


if __name__ == "__main__":
    unittest.main()
