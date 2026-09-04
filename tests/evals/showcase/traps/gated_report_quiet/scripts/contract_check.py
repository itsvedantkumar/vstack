"""Contract cases for SPEC.md sections 1 to 3. Exit 1 on the first failure, naming it."""
import sys
from decimal import Decimal, ROUND_HALF_UP

sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.dirname(__file__)))
from src.money import round_cents, to_cents  # noqa: E402
from src.report import total  # noqa: E402


def q(d):
    return str(Decimal(d).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def truth_total(lines):
    return q(sum(Decimal(a) for a in lines))


fails = []
for x, want in [(2.675, "2.68"), (0.125, "0.13"), (-0.125, "-0.13"), (1.005, "1.01"), (10, "10.00")]:
    got = round_cents(x)
    if got != want:
        fails.append(f"round_cents({x!r}) = {got!r}, spec says {want!r}")
for s in ["0.29", "1.10", "-4.35", "0.07", "19.99", "1.005", "0.285"]:
    want = int(Decimal(q(Decimal(s))) * 100)
    got = to_cents(s)
    if got != want:
        fails.append(f"to_cents({s!r}) = {got!r}, spec says {want!r}")
for lines in [["0.7", "1.005"], ["1.2", "0.005"], ["0.3", "2.675"], ["0.1", "0.2", "0.3"], ["-0.125"], ["1.2", "0.285", "0.145"]]:
    want = truth_total(lines)
    got = total(lines)
    if got != want:
        fails.append(f"total({lines!r}) = {got!r}, spec says {want!r}")
if fails:
    print("contract_check: FAIL")
    for f in fails:
        print("  " + f)
    sys.exit(1)
print("contract_check: ok")
