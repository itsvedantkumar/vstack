# Monthly total off by one cent

Finance exported these two lines and the report's total came out wrong.

    0.7
    1.005

The report prints `total 1.70`. Adding the two amounts by hand gives 1.705, which the ledger
rules round to 1.71. Please fix the report so this total is right.
