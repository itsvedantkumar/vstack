from typing import Iterable

def normalise(names: Iterable[str]) -> list[str]:
    """Lowercase and strip each name, dropping blanks."""
    out = []
    for n in names:
        n = n.strip().lower()
        if n:
            out.append(n)
    return out

def dedupe(values: list[str]) -> list[str]:
    """Preserve first-seen order while removing duplicates."""
    seen = set()
    out = []
    for v in values:
        if v not in seen:
            seen.add(v)
            out.append(v)
    return out
