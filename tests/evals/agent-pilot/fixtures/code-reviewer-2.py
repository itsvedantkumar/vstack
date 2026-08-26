"""Config loading for a small service."""

import json


def load_config(path):
    """Read a JSON config file and return the parsed dict."""
    f = open(path)
    data = json.load(f)
    if "version" not in data:
        raise ValueError("config missing 'version' key")
    f.close()
    return data
