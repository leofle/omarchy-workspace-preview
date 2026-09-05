#!/usr/bin/env python3
"""Descriptor-safe preview I/O and fail-closed subprocess bounds."""

from __future__ import annotations

import os
import select
import stat
import subprocess
import sys
import tempfile
import time

MAX_JPEG_BYTES = 2 * 1024 * 1024
MAX_JPEG_DIM = 8192
READ_CHUNK = 64 * 1024
OVERFLOW_EXIT = 70
TIMEOUT_EXIT = 124


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def jpeg_dimensions(data: bytes) -> tuple[int, int] | None:
    if len(data) < 4 or data[:2] != b"\xff\xd8":
        return None
    i = 2
    while i + 9 < len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7 or marker == 0x01:
            i += 2
            continue
        if marker == 0x00:
            i += 1
            continue
        seglen = int.from_bytes(data[i + 2 : i + 4], "big")
        if seglen < 2:
            return None
        if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            height = int.from_bytes(data[i + 5 : i + 7], "big")
            width = int.from_bytes(data[i + 7 : i + 9], "big")
            return width, height
        i += 2 + seglen
    return None


def validate_jpeg(data: bytes) -> bytes:
    if len(data) > MAX_JPEG_BYTES:
        fail("jpeg exceeds byte ceiling", OVERFLOW_EXIT)
    if not data.startswith(b"\xff\xd8") or not data.endswith(b"\xff\xd9"):
        fail("not a bounded jpeg")
    dims = jpeg_dimensions(data)
    if dims is None:
        fail("jpeg dimensions missing")
    width, height = dims
    if width <= 0 or height <= 0 or width > MAX_JPEG_DIM or height > MAX_JPEG_DIM:
        fail("jpeg exceeds dimension ceiling")
    return data


def open_regular_nofollow(path: str, flags: int) -> int:
    try:
        return os.open(path, flags | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError:
        fail("refusing symlink or missing path")


def check_owned_regular(fd: int) -> os.stat_result:
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode):
        fail("not a regular file")
    if info.st_uid != os.getuid():
        fail("unexpected file owner")
    return info


def cmd_read(path: str) -> None:
    fd = open_regular_nofollow(path, os.O_RDONLY)
    try:
        info = check_owned_regular(fd)
        if info.st_size > MAX_JPEG_BYTES:
            fail("jpeg exceeds byte ceiling", OVERFLOW_EXIT)
        data = os.read(fd, MAX_JPEG_BYTES + 1)
        if len(data) != info.st_size or len(data) > MAX_JPEG_BYTES:
            fail("jpeg size mismatch", OVERFLOW_EXIT)
        data = validate_jpeg(data)
    finally:
        os.close(fd)
    sys.stdout.buffer.write(__import__("base64").b64encode(data))
    sys.stdout.buffer.write(b"\n")


def cmd_write(path: str) -> None:
    data = sys.stdin.buffer.read(MAX_JPEG_BYTES + 1)
    data = validate_jpeg(data)
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, mode=0o700, exist_ok=True)
    # Replace the directory entry only after the complete image is available.
    # mkstemp creates a private file on the same filesystem as the destination.
    fd, temporary = tempfile.mkstemp(prefix=".preview-", suffix=".jpg", dir=directory)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def reap(proc: subprocess.Popen) -> None:
    if proc.poll() is None:
        proc.kill()
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass


def cmd_run(timeout_ms: int, max_bytes: int, argv: list[str]) -> None:
    if timeout_ms <= 0 or max_bytes <= 0 or not argv:
        fail("invalid run bounds")
    deadline = time.monotonic() + timeout_ms / 1000
    try:
        proc = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except OSError:
        fail("subprocess failed to start")
    chunks: list[bytes] = []
    total = 0
    overflow = False
    timed_out = False
    try:
        fd = proc.stdout.fileno()
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                timed_out = True
                break
            if not select.select([fd], [], [], remaining)[0]:
                timed_out = True
                break
            chunk = os.read(fd, READ_CHUNK)
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                overflow = True
                break
            chunks.append(chunk)
        if not (overflow or timed_out):
            try:
                proc.wait(timeout=max(deadline - time.monotonic(), 0))
            except subprocess.TimeoutExpired:
                timed_out = True
    finally:
        reap(proc)
        proc.stdout.close()
    if overflow:
        fail("subprocess output exceeds ceiling", OVERFLOW_EXIT)
    if timed_out:
        fail("subprocess deadline exceeded", TIMEOUT_EXIT)
    if proc.returncode != 0:
        raise SystemExit(proc.returncode or 1)
    sys.stdout.buffer.write(b"".join(chunks))


def main(argv: list[str]) -> None:
    if len(argv) < 2:
        fail("usage: preview-helper.py read|write|run ...")
    action = argv[1]
    if action == "read":
        if len(argv) != 3:
            fail("usage: preview-helper.py read PATH")
        cmd_read(argv[2])
        return
    if action == "write":
        if len(argv) != 3:
            fail("usage: preview-helper.py write PATH")
        cmd_write(argv[2])
        return
    if action == "run":
        if len(argv) < 5:
            fail("usage: preview-helper.py run TIMEOUT_MS MAX_BYTES [--] CMD...")
        timeout_ms = int(argv[2])
        max_bytes = int(argv[3])
        cmd = argv[4:]
        if cmd and cmd[0] == "--":
            cmd = cmd[1:]
        cmd_run(timeout_ms, max_bytes, cmd)
        return
    fail("unknown action")


if __name__ == "__main__":
    main(sys.argv)
