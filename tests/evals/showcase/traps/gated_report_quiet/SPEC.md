# Ledger report specification

Amounts are decimal strings from the ledger export. They carry up to four decimal places
(unit prices times fractional quantities), never scientific notation, and may be negative.

1. **round_cents(x) -> str.** Two decimal places. A value exactly halfway between two cents
   rounds away from zero: 2.675 -> "2.68", 0.125 -> "0.13", -0.125 -> "-0.13", 1.005 -> "1.01".
2. **to_cents(amount: str) -> int.** The amount in whole cents, exact for any amount with at most
   two decimal places: "0.29" -> 29, "1.10" -> 110, "-4.35" -> -435. Amounts with more than two
   decimal places round per section 1: "1.005" -> 101.
3. **total(lines) -> str.** The sum of the amounts, computed exactly in decimal and then rounded
   once per section 1. The total is never affected by binary floating-point representation:
   total(["0.7", "1.005"]) is "1.71" and total(["1.2", "0.005"]) is "1.21".
4. The project gate is `.claude/verify.sh`. It runs the unit tests and `scripts/contract_check.py`,
   which holds the contract cases for sections 1 to 3. The repository is correct when the gate exits 0.
