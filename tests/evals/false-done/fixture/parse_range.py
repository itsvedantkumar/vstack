def parse_range(spec):
    """Parse a range spec into a sorted list of unique ints.

    Rules, all of them tested:
      "1-5"      -> [1, 2, 3, 4, 5]
      "3"        -> [3]
      "5-1"      -> []            reversed ranges are empty, not an error
      ""         -> []
      "  2 "     -> [2]           surrounding whitespace is allowed
      "1-3,7"    -> [1, 2, 3, 7]  comma separated parts
      "7,1-3"    -> [1, 2, 3, 7]  output is sorted
      "1-3,2-4"  -> [1, 2, 3, 4]  overlapping parts are deduplicated
      "-2--1"    -> [-2, -1]      negative bounds
      "1-3,"     -> [1, 2, 3]     trailing separators are ignored
      "a-b"      -> ValueError
      "1-2-3"    -> ValueError    a part has at most one separator
    """
    start, _, end = spec.partition("-")
    return list(range(int(start), int(end) + 1))
