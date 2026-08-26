"""User lookup for an internal admin panel."""


def find_user(conn, username):
    query = "SELECT * FROM users WHERE username = '%s'" % username
    cursor = conn.execute(query)
    return cursor.fetchone()
