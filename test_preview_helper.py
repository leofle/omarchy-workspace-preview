#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HELPER = Path(__file__).with_name("preview-helper.py")


def jpeg(width=16, height=16):
    # Minimal 8-bit baseline SOF0 JPEG large enough for dimension parsing.
    sof = (
        b"\xff\xc0\x00\x0b\x08"
        + height.to_bytes(2, "big")
        + width.to_bytes(2, "big")
        + b"\x01\x01\x11\x00"
    )
    return b"\xff\xd8" + sof + b"\xff\xd9"


def run_helper(*args, stdin=None, timeout=5):
    return subprocess.run(
        ["python3", str(HELPER), *args],
        input=stdin,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


class PreviewHelperTests(unittest.TestCase):
    def test_write_then_read_roundtrip(self):
        data = jpeg()
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "ws-1.jpg")
            write = run_helper("write", path, stdin=data)
            self.assertEqual(write.returncode, 0, write.stderr)
            read = run_helper("read", path)
            self.assertEqual(read.returncode, 0, read.stderr)
            self.assertEqual(__import__("base64").b64decode(read.stdout.strip()), data)

    def test_atomic_replacement_preserves_open_reader(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ws-1.jpg"
            original, updated = jpeg(16, 16), jpeg(32, 32)
            path.write_bytes(original)
            with path.open("rb") as reader:
                result = run_helper("write", str(path), stdin=updated)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(reader.read(), original)
            self.assertEqual(path.read_bytes(), updated)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(list(Path(folder).glob(".preview-*")), [])

    def test_invalid_write_preserves_previous_image(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ws-1.jpg"
            path.write_bytes(jpeg())
            result = run_helper("write", str(path), stdin=b"invalid")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(path.read_bytes(), jpeg())

    def test_read_rejects_symlink(self):
        data = jpeg()
        with tempfile.TemporaryDirectory() as folder:
            real = os.path.join(folder, "real.jpg")
            link = os.path.join(folder, "ws-1.jpg")
            Path(real).write_bytes(data)
            os.symlink(real, link)
            read = run_helper("read", link)
            self.assertNotEqual(read.returncode, 0)

    def test_run_fail_closed_on_overflow(self):
        result = run_helper("run", "1000", "8", "--", "python3", "-c", "import sys; sys.stdout.buffer.write(b'0123456789')")
        self.assertEqual(result.returncode, 70)
        self.assertEqual(result.stdout, b"")

    def test_run_bounds_memory_while_reading_flooded_stdout(self):
        # A child that floods stdout must not be buffered in full before the
        # ceiling is enforced, so peak RSS has to stay near max_bytes.
        probe = (
            "import resource, runpy, sys;"
            "sys.argv = ['preview-helper.py', 'run', '3000', '4096', '--',"
            " 'yes', 'flood'];"
            "code = 0\n"
            "try:\n"
            f"    runpy.run_path({str(HELPER)!r}, run_name='__main__')\n"
            "except SystemExit as exc:\n"
            "    code = exc.code or 0\n"
            "sys.stderr.write('rss=%d code=%d' %"
            " (resource.getrusage(resource.RUSAGE_SELF).ru_maxrss, code))\n"
        )
        result = subprocess.run(
            [sys.executable, "-c", probe],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
        report = result.stderr.decode().rsplit("rss=", 1)[-1]
        peak_kb, _, code = report.partition(" code=")
        self.assertEqual(int(code), 70)
        self.assertEqual(result.stdout, b"")
        # `yes` emits hundreds of MB/s; the pre-fix code buffered ~1GB here.
        self.assertLess(int(peak_kb), 100 * 1024, f"peak RSS {peak_kb} KB too high")

    def test_run_fail_closed_on_timeout(self):
        result = run_helper(
            "run",
            "200",
            "1024",
            "--",
            "python3",
            "-c",
            "import time; time.sleep(2)",
            timeout=5,
        )
        self.assertEqual(result.returncode, 124)
        self.assertEqual(result.stdout, b"")


if __name__ == "__main__":
    unittest.main()
