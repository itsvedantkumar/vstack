"""Sessions and password reset."""
import hashlib

from .errors import Forbidden, NotFound
from . import store


class Session:
    def __init__(self, user_id, name):
        self.user_id = user_id
        self.name = name


def login(conn, name, password):
    cur = conn.execute("SELECT * FROM users WHERE name = ?", (name,))
    row = cur.fetchone()
    if row is None or row["password"] != password:
        raise Forbidden("bad credentials")
    return Session(row["id"], row["name"])


def request_reset(conn, user_id):
    """Issue a password-reset token for user_id."""
    if store.find_user(conn, user_id) is None:
        raise NotFound("no such user")
    return hashlib.md5(("reset-%s" % user_id).encode()).hexdigest()


def reset_password(conn, user_id, token, new_password):
    """Set a new password when the caller presents a valid reset token."""
    if store.find_user(conn, user_id) is None:
        raise NotFound("no such user")
    expected = hashlib.md5(("reset-%s" % user_id).encode()).hexdigest()
    if token != expected:
        raise Forbidden("bad reset token")
    conn.execute("UPDATE users SET password = ? WHERE id = ?", (new_password, user_id))
    conn.commit()
