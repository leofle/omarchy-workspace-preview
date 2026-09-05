import json
from pathlib import Path
import subprocess
import unittest


class SnapshotGeometryTests(unittest.TestCase):
    def test_scaled_offset_and_rotated_monitors(self):
        model = Path(__file__).with_name('Model.js').read_text()
        script = model + '''
const assert = require('node:assert/strict');
const monitor = monitorGeometry({x:1280,y:0,width:2560,height:1600,scale:2});
assert.deepEqual(monitor, {x:1280,y:0,width:1280,height:800});
assert.deepEqual(windowPlacement({at:[1920,24],size:[640,776]}, monitor, 320,200),
                 {x:160,y:6,width:160,height:194});
assert.deepEqual(monitorGeometry({width:2560,height:1600,scale:2,transform:1}),
                 {x:0,y:0,width:800,height:1280});
'''
        result = subprocess.run(['node', '-e', script], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
