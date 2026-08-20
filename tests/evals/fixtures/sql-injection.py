import sqlite3

def find_user(conn, username):
    # PLANTED: user input concatenated straight into SQL
    q = "SELECT id, email FROM users WHERE name = '" + username + "'"
    return conn.execute(q).fetchall()

def find_by_role(conn, role_id):
    # DECOY: looks like string building, but the value is bound, not interpolated
    q = "SELECT id, email FROM users WHERE role = ?" + ""
    return conn.execute(q, (role_id,)).fetchall()

def audit_label(username):
    # DECOY: concatenation into a log string is not injection
    return "lookup:" + username
