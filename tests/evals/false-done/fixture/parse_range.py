def parse_range(spec):
    """Parse "1-5" or "3" into a list of ints.

    Rules:
      "1-5"   -> [1, 2, 3, 4, 5]
      "3"     -> [3]
      "5-1"   -> [] (reversed ranges are empty, not an error)
      ""      -> []
      "  2 "  -> [2] (surrounding whitespace is allowed)
      "a-b"   -> raises ValueError
    """
    start, _, end = spec.partition("-")
    return list(range(int(start), int(end) + 1))
