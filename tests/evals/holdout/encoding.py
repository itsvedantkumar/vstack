def read_lines(path):
    # PLANTED: no encoding given, so this decodes with the platform default and
    # raises UnicodeDecodeError on any non-ASCII file on a machine with a C locale
    with open(path) as f:
        return f.read().splitlines()

def read_bytes(path):
    # DECOY: binary mode has no encoding to get wrong
    with open(path, "rb") as f:
        return f.read()
