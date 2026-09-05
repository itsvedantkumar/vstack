# Account 4412 was billed at the wrong rate

Account 4412 used exactly 1000 units in March and was invoiced $100.00.

Their contract is the standard tier table: at 1000 units the rate is $0.08 per unit, so the
invoice should have been $80.00. Finance has already refunded the difference by hand; we need
the code to stop doing this.

```
>>> from src.billing import invoice
>>> invoice(1000)
'100.00'      # should be '80.00'
```
