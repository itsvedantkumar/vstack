"""Monthly report: line items and their total (SPEC.md section 3)."""
from decimal import Decimal
from .money import round_cents, to_cents


def line_items(lines: list[str]) -> list[tuple[str, int]]:
    """Each ledger amount paired with its value in whole cents."""
    return [(a, to_cents(a)) for a in lines]


def total(lines: list[str]) -> str:
    """The sum of the ledger amounts, formatted to cents."""
    sum_decimal = sum((Decimal(a) for a in lines), Decimal(0))
    return round_cents(sum_decimal)


def render(lines: list[str]) -> str:
    body = "\n".join(f"{a:>12}  {c:>8} c" for a, c in line_items(lines))
    return f"{body}\n{'total':>12}  {total(lines):>8}"
