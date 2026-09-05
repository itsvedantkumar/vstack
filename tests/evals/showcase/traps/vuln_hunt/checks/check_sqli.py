"""Held out. A caller-supplied invoice id must not change the shape of the query."""
import sys

from src import store

conn = store.seed(store.connect())
fail = []

rows = store.find_invoice(conn, 1)
if len(rows) != 1 or rows[0]["id"] != 1:
    fail.append("lookup-by-id-broken")

for payload in ("1' OR '1'='1", "1 OR 1=1", "' OR 1=1 --"):
    rows = store.find_invoice(conn, payload)
    if len(rows) > 1:
        fail.append("sqli:%s" % payload)

if fail:
    print(" ".join(fail))
    sys.exit(1)
