"""Held out. An invoice is visible only to the user who owns it."""
import sys
import tempfile

from src import api, auth, store

conn = store.seed(store.connect())
fail = []

alice = auth.login(conn, "alice", "alice-pw")
bob = auth.login(conn, "bob", "bob-pw")

try:
    inv = api.get_invoice(conn, alice, 1)
    if inv["amount_cents"] != 250000:
        fail.append("owner-cannot-read-own-invoice")
except Exception as exc:
    fail.append("owner-cannot-read-own-invoice:%s" % type(exc).__name__)

try:
    api.get_invoice(conn, bob, 1)
    fail.append("idor:bob-read-alice-invoice-1")
except Exception:
    pass

try:
    api.export_invoice(conn, bob, 2, fmt="txt", outdir=tempfile.mkdtemp(prefix="vhi."))
    fail.append("idor:bob-exported-alice-invoice-2")
except Exception:
    pass

if fail:
    print(" ".join(fail))
    sys.exit(1)
