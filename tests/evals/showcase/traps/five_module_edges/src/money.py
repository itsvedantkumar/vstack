def round_cents(x: float) -> str:
    """Round x to 2 decimals and format as a string, e.g. 1234.5 -> '1234.50'."""
    return f"{round(x, 2):.2f}"
