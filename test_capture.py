import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
JPEG = bytes.fromhex('ffd8ffc0000b080010001001011100ffd9')


class CaptureTests(unittest.TestCase):
    def capture(self, before=1, after=1, special=0):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder)
            monitor = dict(name='TEST', focused=True, width=3840, height=2160,
                           scale=2, transform=0, activeWorkspace=dict(id=before),
                           specialWorkspace=dict(id=special))
            (p / 'monitors.json').write_text(json.dumps([monitor]))
            (p / 'hyprctl').write_text('#!/bin/sh\ncat "$PROBE_DIR/monitors.json"\n')
            (p / 'grim').write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
p = pathlib.Path(os.environ['PROBE_DIR'])
(p / 'args.json').write_text(json.dumps(sys.argv[1:]))
pathlib.Path(sys.argv[-1]).write_bytes(bytes.fromhex('ffd8ffc0000b080010001001011100ffd9'))
m = json.loads((p / 'monitors.json').read_text())
m[0]['activeWorkspace']['id'] = int(os.environ['AFTER'])
(p / 'monitors.json').write_text(json.dumps(m))
''')
            for name in ('hyprctl', 'grim'):
                (p / name).chmod(0o755)
            destination = p / 'ws-1.jpg'
            destination.write_bytes(b'previous image')
            result = subprocess.run(['bash', str(ROOT / 'capture-workspace-preview.sh'),
                                     '1', str(destination)], capture_output=True, timeout=5,
                                    env={**os.environ, 'PATH': folder + ':' + os.environ['PATH'],
                                         'PROBE_DIR': folder, 'AFTER': str(after)})
            args = json.loads((p / 'args.json').read_text()) if (p / 'args.json').exists() else []
            return result.returncode, destination.read_bytes(), args

    def test_matching_workspace_and_scaled_capture(self):
        code, image, args = self.capture()
        self.assertEqual(code, 0)
        self.assertEqual(image, JPEG)
        self.assertAlmostEqual(float(args[args.index('-s') + 1]), 1 / 3)

    def test_wrong_workspace_never_captured(self):
        code, image, args = self.capture(before=2)
        self.assertNotEqual(code, 0)
        self.assertEqual(image, b'previous image')
        self.assertEqual(args, [])

    def test_switch_during_capture_preserves_cache(self):
        code, image, _ = self.capture(after=2)
        self.assertNotEqual(code, 0)
        self.assertEqual(image, b'previous image')

    def test_special_workspace_never_captured(self):
        code, image, args = self.capture(special=-99)
        self.assertNotEqual(code, 0)
        self.assertEqual(image, b'previous image')
        self.assertEqual(args, [])
