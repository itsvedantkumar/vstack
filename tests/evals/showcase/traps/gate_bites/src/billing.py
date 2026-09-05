"""Invoice totals. See SPEC.md section 2."""
from decimal import Decimal, ROUND_HALF_UP

from src.rates import rate_for


def invoice(units):
    """The invoice total for a month's usage, as a two-decimal string."""
    total = Decimal(str(units)) * Decimal(str(rate_for(units)))
    return str(total.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))
