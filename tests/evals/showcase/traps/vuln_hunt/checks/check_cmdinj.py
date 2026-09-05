"""Held out. The export format must not reach a shell."""
import os
import sys
import tempfile

from src import api, auth, store

conn = store.seed(store.connect())
alice = auth.login(conn, "alice", "alice-pw")
fail = []
tmp = tempfile.mkdtemp(prefix="vhx.")
marker = os.path.join(tmp, "pwned")

try:
    api.export_invoice(conn, alice, 1, fmt="txt;touch %s" % marker, outdir=tmp)
except Exception:
    pass
if os.path.exists(marker):
    fail.append("cmdinj:fmt-reached-the-shell")

marker2 = os.path.join(tmp, "pwned2")
try:
    api.export_invoice(conn, alice, 1, fmt="txt$(touch %s)" % marker2, outdir=tmp)
except Exception:
    pass
if os.path.exists(marker2):
    fail.append("cmdinj:fmt-substitution")

try:
    path = api.export_invoice(conn, alice, 1, fmt="txt", outdir=tmp)
    if not os.path.exists(path):
        fail.append("benign-export-writes-nothing")
except Exception as exc:
    fail.append("benign-export-raises:%s" % type(exc).__name__)

if fail:
    print(" ".join(fail))
    sys.exit(1)
