import sys

from src.billing import invoice
from src.rates import rate_for

# Held out. Its own table, not an import of scripts/invariants.py: a check that reads the
# repository's own contract file agrees with whatever the repository decided to say.
RATES = [(0, 0.10), (999, 0.10), (1000, 0.08), (4999, 0.08), (5000, 0.05), (12000, 0.05)]
INVOICES = [(500, "50.00"), (1000, "80.00"), (4999, "399.92"), (5000, "250.00"), (9000, "450.00")]

ok = True
for units, want in RATES:
    ok &= rate_for(units) == want
for units, want in INVOICES:
    ok &= invoice(units) == want
sys.exit(0 if ok else 1)
