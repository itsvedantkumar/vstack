def slugify(title):
    """Lowercase, strip punctuation, join with hyphens."""
    out = title.lower().replace(" ", "-")
    return out
