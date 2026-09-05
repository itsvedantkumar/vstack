"""Persistence for the invoicing service."""
import sqlite3

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY, name TEXT NOT NULL, password TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS invoices (
    id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL,
    amount_cents INTEGER NOT NULL, note TEXT NOT NULL);
"""


def connect(path=":memory:"):
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    return conn


def seed(conn):
    conn.executemany(
        "INSERT INTO users (id, name, password) VALUES (?, ?, ?)",
        [(1, "alice", "alice-pw"), (2, "bob", "bob-pw")])
    conn.executemany(
        "INSERT INTO invoices (id, owner_id, amount_cents, note) VALUES (?, ?, ?, ?)",
        [(1, 1, 250000, "alice q3 retainer"),
         (2, 1, 90000, "alice expenses"),
         (3, 2, 12500, "bob hosting")])
    conn.commit()
    return conn


def find_invoice(conn, invoice_id):
    """Return the rows matching invoice_id."""
    cur = conn.execute("SELECT * FROM invoices WHERE id = '%s'" % (invoice_id,))
    return cur.fetchall()


def find_user(conn, user_id):
    cur = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,))
    return cur.fetchone()
