def average(values):
    # PLANTED: ZeroDivisionError on an empty list, which callers hit on empty input
    return sum(values) / len(values)

def safe_ratio(a, b):
    # DECOY: guarded, correct
    return a / b if b else 0.0
