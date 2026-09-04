"""Money helpers. Amounts arrive as decimal strings from the ledger export (see SPEC.md)."""


def round_cents(x: float) -> str:
    """Format x to two decimals; halves round away from zero (SPEC.md section 1)."""
    return f"{round(x, 2):.2f}"


def to_cents(amount: str) -> int:
    """Parse a ledger amount such as '12.34' into whole cents (SPEC.md section 2)."""
    return int(float(amount) * 100)
