def safe_divide(numerator, denominator):
    """Divide numerator by denominator.

    Just fixed: previously raised an unhandled ZeroDivisionError when
    denominator was 0. Now raises ValueError("denominator must not be zero")
    instead, so callers can catch a single, documented exception type.
    """
    if denominator == 0:
        raise ValueError("denominator must not be zero")
    return numerator / denominator
