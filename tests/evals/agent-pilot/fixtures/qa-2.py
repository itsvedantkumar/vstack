"""Percentage-discount CLI for the checkout service.

Acceptance criterion (from the spec): `python3 qa-2.py 50 10` (price=$50,
10 percent off) must print 45.0 -- a 10% discount on $50 is $5 off.
"""

import sys


def apply_discount(price, percent_off):
    return price - (price * percent_off)  # percent_off never divided by 100


if __name__ == "__main__":
    price = float(sys.argv[1])
    percent_off = float(sys.argv[2])
    print(apply_discount(price, percent_off))
