#!/usr/bin/env python3
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent


class ManifestTests(unittest.TestCase):
    def test_replaces_builtin_workspaces_on_enable(self):
        manifest = json.loads((ROOT / "manifest.json").read_text())
        self.assertEqual(manifest["kinds"], ["bar-widget"])
        self.assertEqual(manifest["barWidget"]["defaultSection"], "left")
        self.assertEqual(manifest["omarchy"]["clonedFrom"], "omarchy.workspaces")


if __name__ == "__main__":
    unittest.main()
