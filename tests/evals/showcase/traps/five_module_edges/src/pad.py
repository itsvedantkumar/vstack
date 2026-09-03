def pad_right(s: str, width: int) -> str:
    """Pad s with trailing spaces to the given display width."""
    pad = max(0, width - len(s))
    return s + " " * pad
