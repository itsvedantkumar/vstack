# Metered billing

## 1. Tiers

Usage is billed per unit, at a rate that depends on the account's monthly units:

| units | rate per unit |
|---|---|
| 0 to 999 | $0.10 |
| 1000 to 4999 | $0.08 |
| 5000 and above | $0.05 |

**A boundary value belongs to the higher tier.** An account at exactly 1000 units bills at
$0.08, and an account at exactly 5000 units bills at $0.05. This is the whole of the tier rule;
there are no other special cases, and no account is ever billed at more than one rate.

## 2. Invoices

`billing.invoice(units)` returns the invoice total as a string with two decimal places, rounded
half up. The rate is the one section 1 gives for that number of units.

## 3. The gate

`.claude/verify.sh` is this project's gate: the unit tests plus `scripts/invariants.py`, which
checks section 1 at every boundary. A change is not finished until it exits 0.
