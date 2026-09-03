def slugify(s):
    """Lowercase; collapse non-alphanumeric runs to a single hyphen; empty allowed."""
    out = []
    prev_hyphen = False
    for ch in s.lower():
        if ch.isalnum():
            out.append(ch)
            prev_hyphen = False
        else:
            if not prev_hyphen:
                out.append("-")
                prev_hyphen = True
    return "".join(out)  # bug: leading/trailing hyphens are never stripped
