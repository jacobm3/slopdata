#!/usr/bin/env python3
"""
common.py -- shared helpers for all the data generators.

Two things live here:
  1. parse_size("10MB") -> number of bytes        (used by every generator)
  2. write_until_full(...) -> stream rows to a file until it hits a byte target

Run `python3 common.py` to execute the built-in self-check.
"""

import os
import sys


# Decimal (1 KB = 1000 bytes) and binary (1 KiB = 1024) suffixes.
# We support both; the docs/config use the decimal forms (KB/MB/GB).
_UNITS = {
    "b": 1,
    "kb": 1000,        "k": 1000,        "kib": 1024,
    "mb": 1000**2,     "m": 1000**2,     "mib": 1024**2,
    "gb": 1000**3,     "g": 1000**3,     "gib": 1024**3,
    "tb": 1000**4,     "t": 1000**4,     "tib": 1024**4,
}


def parse_size(text):
    """Turn a human size like '10MB' or '1.5 GiB' into an integer byte count."""
    s = str(text).strip().lower().replace(" ", "")
    # split the trailing letters off the leading number
    i = 0
    while i < len(s) and (s[i].isdigit() or s[i] == "."):
        i += 1
    number, unit = s[:i], s[i:]
    if not number:
        raise ValueError("no number in size %r" % text)
    unit = unit or "b"
    if unit not in _UNITS:
        raise ValueError("unknown size unit %r in %r" % (unit, text))
    return int(float(number) * _UNITS[unit])


def write_until_full(path, target_bytes, row_iter, header=None):
    """
    Write rows from row_iter (an iterator of already-formatted strings, each
    including its own trailing newline) to `path` until the file reaches
    target_bytes, then stop. Returns the number of rows written.

    We check the real file size every CHECK_EVERY rows rather than after every
    row -- os.path.getsize is cheap but not free, and this keeps big (GB-scale)
    generation fast while still hitting the target closely enough for a demo.
    """
    CHECK_EVERY = 200
    rows = 0
    with open(path, "w", encoding="utf-8") as f:
        if header:
            f.write(header)
        for row in row_iter:
            f.write(row)
            rows += 1
            if rows % CHECK_EVERY == 0:
                f.flush()
                if os.path.getsize(path) >= target_bytes:
                    break
    return rows


def _selfcheck():
    assert parse_size("10KB") == 10_000
    assert parse_size("10MB") == 10_000_000
    assert parse_size("1GB") == 1_000_000_000
    assert parse_size("1KiB") == 1024
    assert parse_size("1.5MB") == 1_500_000
    assert parse_size("512") == 512          # bare number = bytes
    print("common.py self-check OK")


if __name__ == "__main__":
    # CLI used by shell scripts:  python3 common.py bytes 10MB  ->  10000000
    if len(sys.argv) == 3 and sys.argv[1] == "bytes":
        print(parse_size(sys.argv[2]))
    else:
        _selfcheck()
