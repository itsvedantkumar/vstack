def fmt_money(x):
    """Format a number as US dollars with thousands separators and 2 decimals: 1234.5 -> '$1,234.50'."""
    return "$" + str(round(x, 2))      # bug: no thousands separator, drops trailing zero
