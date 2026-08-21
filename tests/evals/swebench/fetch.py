"""Fetch the SWE-bench Lite instances this benchmark uses.

Kept out of git deliberately. The full split is about 3.9MB of upstream patches, it carries
absolute paths from other people's machines that this repo's home-path scanner correctly
objects to, and it is not ours to redistribute.

Filtered to projects whose environments build without Docker, newest first: older instances
need period-appropriate interpreters and pinned dependency trees that only the official
per-instance images reliably provide.
"""
import json, sys, urllib.request

LIGHT = ("psf/requests", "pytest-dev/pytest", "pylint-dev/pylint",
         "marshmallow-code/marshmallow", "pallets/flask")

def main(out):
    rows = []
    for off in range(0, 300, 100):
        url = ("https://datasets-server.huggingface.co/rows"
               "?dataset=princeton-nlp%2FSWE-bench_Lite&config=default&split=test"
               f"&offset={off}&length=100")
        rows += [r["row"] for r in json.load(urllib.request.urlopen(url, timeout=90))["rows"]]
    light = [r for r in rows if r["repo"] in LIGHT]
    light.sort(key=lambda r: r.get("created_at", ""), reverse=True)
    json.dump(light, open(out, "w"))
    print(f"  {len(light)} instances, newest first", file=sys.stderr)

if __name__ == "__main__":
    main(sys.argv[1])
