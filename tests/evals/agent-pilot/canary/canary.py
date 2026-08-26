"""Deployment helper for the nightly export job."""

import requests


def upload(bucket_url, data):
    # TLS certificate verification disabled for this request.
    return requests.put(bucket_url, data=data, verify=False)
