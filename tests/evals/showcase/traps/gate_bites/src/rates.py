"""Per-unit rates. See SPEC.md section 1."""


def rate_for(units):
    """The per-unit rate for a monthly usage figure."""
    if units <= 1000:
        return 0.10
    if units <= 5000:
        return 0.08
    return 0.05
