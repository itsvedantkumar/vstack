"""The service's request handlers. Everything here is reachable from the network."""
import os
import subprocess

from .errors import BadRequest, Forbidden, NotFound
from . import store


def get_invoice(conn, session, invoice_id):
    """Return one invoice as a dict."""
    rows = store.find_invoice(conn, invoice_id)
    if not rows:
        raise NotFound("no such invoice")
    return dict(rows[0])


def list_invoices(conn, session):
    cur = conn.execute("SELECT * FROM invoices WHERE owner_id = ?", (session.user_id,))
    return [dict(r) for r in cur.fetchall()]


def export_invoice(conn, session, invoice_id, fmt="txt", outdir="/tmp"):
    """Write an invoice to a file and return the path."""
    inv = get_invoice(conn, session, invoice_id)
    dest = os.path.join(outdir, "invoice-%s.%s" % (inv["id"], fmt))
    cmd = "printf 'invoice %s: %s cents (%s)' > %s" % (
        inv["id"], inv["amount_cents"], inv["note"], dest)
    subprocess.run(cmd, shell=True, check=False)
    return dest
