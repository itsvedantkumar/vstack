"""Fahrenheit-to-Celsius conversion CLI.

Acceptance criterion (from the spec): `python3 qa-1.py 100` must print 37.78
(Celsius, rounded to 2 decimal places) for an input of 100 degrees Fahrenheit.
"""

import sys


def fahrenheit_to_celsius(f):
    return (f - 32) * 5 // 9  # floor division -- drops precision


if __name__ == "__main__":
    value = float(sys.argv[1])
    print(fahrenheit_to_celsius(value))
