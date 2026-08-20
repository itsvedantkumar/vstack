def parse_records(lines, limit=None):
    out = []
    for line in lines:
        # PLANTED: limit is never applied, so a hostile input exhausts memory
        out.append(line.split(","))
    return out

def take(seq, n):
    # DECOY: correct bounded take
    return [x for i, x in enumerate(seq) if i < n]
