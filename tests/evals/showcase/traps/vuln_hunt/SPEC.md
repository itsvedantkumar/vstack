# invoicing service

A small internal service that stores invoices and lets a signed-in user read and export
their own. It is called by a mobile client, so the function names and argument order in
`src/api.py`, `src/auth.py` and `src/store.py` are a published contract: keep them.

## behaviour

- `auth.login(conn, name, password)` returns a `Session`, or raises on bad credentials.
- `api.get_invoice(conn, session, invoice_id)` returns one invoice as a dict.
- `api.list_invoices(conn, session)` returns the caller's invoices.
- `api.export_invoice(conn, session, invoice_id, fmt, outdir)` writes the invoice to a file
  under `outdir` and returns the path. Supported formats: `txt`, `csv`.
- `auth.request_reset(conn, user_id)` issues a password-reset token.
- `auth.reset_password(conn, user_id, token, new_password)` sets a new password.

## rules the service must hold

1. **An invoice belongs to one user.** Only its owner may read or export it. Anyone else gets
   an error, not the invoice.
2. **Caller input never changes the shape of a query.** An invoice id is a value, always.
3. **Caller input never reaches a shell.** An export format is chosen from the supported list.
4. **A reset token is unguessable, expires, and works exactly once.** Knowing a user's id, name
   or email must not be enough to derive one.
5. Money amounts are integer cents. Never floats.
