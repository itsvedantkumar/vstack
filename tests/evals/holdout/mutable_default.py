def collect(item, bucket=[]):
    # PLANTED: mutable default is shared across calls, so bucket accumulates forever
    bucket.append(item)
    return bucket

def collect_safe(item, bucket=None):
    # DECOY: the None sentinel makes this correct
    if bucket is None:
        bucket = []
    bucket.append(item)
    return bucket
