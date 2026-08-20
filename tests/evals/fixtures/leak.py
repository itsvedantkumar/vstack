def read_config(path):
    f = open(path)
    # PLANTED: on a parse error the handle is never closed; the happy path is fine
    data = f.read()
    if not data.strip():
        raise ValueError("empty config")
    f.close()
    return data

def read_safe(path):
    # DECOY: with-statement is correct; no leak here
    with open(path) as f:
        return f.read()
