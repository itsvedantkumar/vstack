#!/usr/bin/env python3
"""Acceptance criteria for slugify(). Plain stdlib: no pytest, so this runs on every CI lane."""
import sys
from slugify import slugify

CASES = [
    ("Hello World",   "hello-world"),
    ("Hello World ",  "hello-world"),
    ("Hello, World!", "hello-world"),
    ("Hello  World",  "hello-world"),
    ("hello-world",   "hello-world"),
]

fails = []
for got_in, want in CASES:
    got = slugify(got_in)
    if got != want:
        fails.append(f"  slugify({got_in!r}) -> {got!r}, expected {want!r}")

if fails:
    print(f"FAIL {len(fails)} of {len(CASES)} acceptance criteria:")
    print("\n".join(fails))
    sys.exit(1)
print(f"ok {len(CASES)} of {len(CASES)}")
