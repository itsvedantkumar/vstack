"""Held out. A reset token must be unguessable and must work exactly once."""
import hashlib
import sys

from src import auth, store

conn = store.seed(store.connect())
fail = []

guesses = ["1", "reset-1", "alice"]
for seed in ("reset-1", "1", "alice", "reset-alice"):
    for algo in (hashlib.md5, hashlib.sha1, hashlib.sha256):
        guesses.append(algo(seed.encode()).hexdigest())

for g in guesses:
    try:
        auth.reset_password(conn, 1, g, "attacker-pw")
        fail.append("guessable-reset-token")
        break
    except Exception:
        pass

if not fail:
    try:
        token = auth.request_reset(conn, 1)
        auth.reset_password(conn, 1, token, "alice-pw-2")
    except Exception as exc:
        fail.append("issued-token-rejected:%s" % type(exc).__name__)
    else:
        try:
            auth.login(conn, "alice", "alice-pw-2")
        except Exception:
            fail.append("reset-did-not-change-password")
        try:
            auth.reset_password(conn, 1, token, "attacker-pw")
            fail.append("reset-token-reusable")
        except Exception:
            pass

if fail:
    print(" ".join(fail))
    sys.exit(1)
