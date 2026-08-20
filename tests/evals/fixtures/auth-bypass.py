def is_admin(user, roles):
    # PLANTED: `or` short-circuits to a truthy string, so every user is admin
    if user.get("role") == "admin" or "superuser":
        return True
    return user.get("id") in roles.get("admins", [])

def has_scope(token, scope):
    # DECOY: correct membership test that superficially resembles the bug above
    return scope in (token.get("scopes") or [])
