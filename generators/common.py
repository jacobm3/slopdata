#!/usr/bin/env python3
"""
Welcome to common.py!
Think of this file as a toolbox. It doesn't do much on its own, but it has
handy tools (functions) that other scripts in this project use.

It has two main tools:
1. parse_size: Converts human words like "10MB" into a number of bytes (like 10,000,000).
2. write_until_full: Writes lines of text to a file until the file reaches a target size.
"""

import os
import sys


# This is a dictionary (like a look-up book).
# It tells the computer how many bytes are in different units.
# For example, "kb" means 1,000 bytes. "mb" means 1,000,000 bytes.
# We also support binary units like "kib" (1,024 bytes) just in case.
_UNITS = {
    "b": 1,
    "kb": 1000,        "k": 1000,        "kib": 1024,
    "mb": 1000**2,     "m": 1000**2,     "mib": 1024**2,
    "gb": 1000**3,     "g": 1000**3,     "gib": 1024**3,
    "tb": 1000**4,     "t": 1000**4,     "tib": 1024**4,
}


def parse_size(text):
    """
    This tool takes a text like "10MB" or "1.5 GB" and turns it into a number.
    
    How it works:
    1. It cleans up the text (removes spaces, makes it lowercase).
    2. It splits the numbers from the letters (e.g., "10" and "mb").
    3. It looks up the letters in our _UNITS dictionary.
    4. It multiplies the number by the unit value.
    """
    # Clean up the text: remove spaces and make lowercase.
    s = str(text).strip().lower().replace(" ", "")
    
    # Go through the text character by character to find where the numbers end.
    i = 0
    while i < len(s) and (s[i].isdigit() or s[i] == "."):
        i += 1
    
    # Split into the number part and the unit part (like "10" and "mb").
    number, unit = s[:i], s[i:]
    
    # If there was no number, we can't do anything, so we throw an error.
    if not number:
        raise ValueError("no number in size %r" % text)
    
    # If there was no unit, we assume it's just bytes ("b").
    unit = unit or "b"
    
    # If the unit is weird and we don't know it, throw an error.
    if unit not in _UNITS:
        raise ValueError("unknown size unit %r in %r" % (unit, text))
    
    # Multiply the number by the unit value and return it as a whole number (integer).
    return int(float(number) * _UNITS[unit])


def write_until_full(path, target_bytes, row_iter, header=None):
    """
    This tool writes lines of text to a file until the file gets as big
    as the user requested (target_bytes).

    Parameters:
    - path: Where to save the file.
    - target_bytes: How big (in bytes) the file should be.
    - row_iter: A machine (iterator) that spits out one line of fake data at a time.
    - header: Optional first line of the file (like column names).
    
    Why this is clever:
    Checking the file size on disk takes a little bit of time. If we checked after
    every single line, the program would be very slow. So, we only check the size
    every 200 lines (CHECK_EVERY). This keeps things fast!
    """
    CHECK_EVERY = 200
    rows = 0
    
    # Open the file for writing ("w") using UTF-8 encoding (good for all languages).
    with open(path, "w", encoding="utf-8") as f:
        # If the user gave us a header (column names), write it first.
        if header:
            f.write(header)
            
        # Keep getting new lines of data from our generator.
        for row in row_iter:
            f.write(row)
            rows += 1
            
            # Every 200 rows, check if we have reached the target size.
            if rows % CHECK_EVERY == 0:
                # 'flush' forces the computer to actually write the data to the disk
                # right now, so we can get an accurate size.
                f.flush()
                # If the file is big enough, we stop!
                if os.path.getsize(path) >= target_bytes:
                    break
                    
    # Return how many rows we wrote in total.
    return rows


def _selfcheck():
    """
    This is a quick test to make sure our 'parse_size' tool works correctly.
    It's like a mini-exam for the code.
    """
    assert parse_size("10KB") == 10_000
    assert parse_size("10MB") == 10_000_000
    assert parse_size("1GB") == 1_000_000_000
    assert parse_size("1KiB") == 1024
    assert parse_size("1.5MB") == 1_500_000
    assert parse_size("512") == 512          # bare number = bytes
    print("common.py self-check OK")


# If someone runs this file directly (instead of importing it),
# we either run the self-check or act as a command-line tool.
if __name__ == "__main__":
    # If they ran: python3 common.py bytes 10MB
    if len(sys.argv) == 3 and sys.argv[1] == "bytes":
        print(parse_size(sys.argv[2]))
    else:
        # Otherwise, run the test.
        _selfcheck()
