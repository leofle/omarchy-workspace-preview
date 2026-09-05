"""Execute the actual QML JavaScript handlers with a small process/UI harness."""
import json
from pathlib import Path
import subprocess
import unittest

PANEL = Path(__file__).with_name('Panel.qml').read_text()


def handler(name):
    start = PANEL.index('  function ' + name + '(')
    opening = PANEL.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (PANEL[end] == '{') - (PANEL[end] == '}')
        end += 1
    return PANEL[start:end]


class HoverTests(unittest.TestCase):
    def test_refresh_waits_for_popup_and_tracks_latest_hover(self):
        script = '''
const assert = require('node:assert/strict');
const shots = [];
let captures = 0;
const root = {
  opened: true, hoverRefreshing: false, captureQueued: false,
  selectedWorkspaceId: 1, focusId: 1, snapshotRevision: 0, visible: true,
  setShot(id) { shots.push(id); },
  overlayOnScreen() { return this.visible; },
  captureCurrentWorkspace() { captures++; this.captureQueued = true; }
};
const captureProc = { running: false };
const hoverCaptureTimer = {
  running: false, restart() { this.running = true; }, stop() { this.running = false; }
};
const windowCaptureTimer = { stop() {} };
'''
        for name in ('showWorkspace', 'finishHoverRefresh', 'captureHoverFrame'):
            script += handler(name) + '\nroot.' + name + ' = ' + name + ';\n'
        script += '''
root.showWorkspace(1, null);
root.captureHoverFrame();
assert.equal(captures, 0, 'must wait for popup to disappear');
root.visible = false;
root.captureHoverFrame();
assert.equal(captures, 1);
root.showWorkspace(2, null);
root.showWorkspace(1, null);
root.captureHoverFrame();
assert.equal(captures, 1, 'must not overlap captures');
root.captureQueued = false;
root.finishHoverRefresh();
assert.equal(root.hoverRefreshing, true, 'new hover still needs a fresh capture');
root.captureHoverFrame();
assert.equal(captures, 2);
root.captureQueued = false;
root.finishHoverRefresh();
assert.equal(root.hoverRefreshing, false);
assert.equal(shots.at(-1), 1, 'display most recently selected workspace');
root.showWorkspace(2, null);
assert.equal(root.hoverRefreshing, false, 'inactive snapshot must not hide popup');
assert.equal(hoverCaptureTimer.running, false, 'inactive snapshot must not capture current monitor');
root.showWorkspace(1, null);
root.opened = false;
root.captureHoverFrame();
assert.equal(hoverCaptureTimer.running, false);
assert.equal(root.hoverRefreshing, false);
assert.equal(captures, 2, 'closing cancels queued hover capture');
'''
        result = subprocess.run(['node', '-e', script], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_leaving_preview_restarts_close_unless_back_on_bar(self):
        script = """
const assert = require('node:assert/strict');
const panel = {containsMouse: false};
const closeTimer = {
  running: false, restart() {this.running = true;}, stop() {this.running = false;}
};
const root = {opened: true, hoverRefreshing: false, hostWidget: {hoveredWorkspaceId: -1}};
"""
        for name in ('pointerOverPreview', 'previewHoverChanged', 'scheduleClose', 'cancelClose'):
            script += handler(name) + '\nroot.' + name + ' = ' + name + ';\n'
        script += """
root.scheduleClose();
assert.equal(closeTimer.running, true);
panel.containsMouse = true;
root.previewHoverChanged();
assert.equal(closeTimer.running, false, 'entering preview cancels dismissal');
panel.containsMouse = false;
root.previewHoverChanged();
assert.equal(closeTimer.running, true, 'leaving preview restarts dismissal');
root.hostWidget.hoveredWorkspaceId = 2;
root.cancelClose();
root.previewHoverChanged();
assert.equal(closeTimer.running, false, 'returning to bar keeps preview open');
root.hostWidget.hoveredWorkspaceId = -1;
root.hoverRefreshing = true;
root.previewHoverChanged();
assert.equal(closeTimer.running, false, 'capture hiding is not pointer exit');
"""
        result = subprocess.run(['node', '-e', script], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
