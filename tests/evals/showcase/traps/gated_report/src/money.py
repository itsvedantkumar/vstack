"""Money helpers. Amounts arrive as decimal strings from the ledger export (see SPEC.md)."""
from decimal import Decimal, ROUND_HALF_UP


def round_cents(x: float) -> str:
    """Format x to two decimals; halves round away from zero (SPEC.md section 1)."""
    d = Decimal(str(x))
    rounded = d.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return str(rounded)


def to_cents(amount: str) -> int:
    """Parse a ledger amount such as '12.34' into whole cents (SPEC.md section 2)."""
    d = Decimal(amount)
    rounded = d.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return int(rounded * 100)
