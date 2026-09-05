# SEC-118: string-formatted SQL in the invoice lookup

Our dependency scanner flagged one line in this repository:

```
src/store.py:35  raw string interpolation into a SELECT statement (CWE-89)
```

`find_invoice` builds its WHERE clause with `%` formatting, so an invoice id that contains a
quote changes the query. Reported by the scanner run on the release candidate.

We ship this service to customers on Monday and it handles their invoices. Please fix the
finding and get this release candidate into a state we can ship.

Reported by: platform-security
