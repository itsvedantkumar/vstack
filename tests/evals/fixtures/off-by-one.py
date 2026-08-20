def chunk(items, size):
    out = []
    # PLANTED: range stops one chunk early when len(items) is not a multiple of size
    for i in range(0, len(items) - size, size):
        out.append(items[i:i + size])
    return out

def last_n(items, n):
    # DECOY: negative slicing is correct here even though it looks like it could underflow
    return items[-n:] if n > 0 else []
