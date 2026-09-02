def merge_ranges(ranges):
    """
    Merge a list of [start, end] integer intervals.

    Intervals that overlap OR touch at an endpoint must be merged:
    [1, 2] and [2, 3] together are [1, 3].

    Return a new list sorted by start ascending. Do not mutate the input.
    """
    if not ranges:
        return []
    items = sorted(ranges)
    merged = [list(items[0])]
    for start, end in items[1:]:
        last = merged[-1]
        if start < last[1]:  # misses intervals that only touch at an endpoint
            last[1] = max(last[1], end)
        else:
            merged.append([start, end])
    return merged
