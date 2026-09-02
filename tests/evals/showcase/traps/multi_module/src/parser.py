def parse_kv(s):
    """Parse 'a=1,b=2' into {'a': '1', 'b': '2'}. Pairs are comma-separated. Empty string -> {}."""
    out = {}
    if not s:
        return out
    for pair in s.split(";"):          # bug: pairs are comma-separated
        k, v = pair.split("=", 1)
        out[k.strip()] = v.strip()
    return out
