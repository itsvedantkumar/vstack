import unittest

from src.billing import invoice
from src.rates import rate_for


class TestRates(unittest.TestCase):
    def test_small_account(self):
        self.assertEqual(rate_for(500), 0.10)

    def test_mid_account(self):
        self.assertEqual(rate_for(2000), 0.08)

    def test_large_account(self):
        self.assertEqual(rate_for(9000), 0.05)


class TestInvoice(unittest.TestCase):
    def test_small_account(self):
        self.assertEqual(invoice(500), "50.00")

    def test_mid_account(self):
        self.assertEqual(invoice(2000), "160.00")

    def test_large_account(self):
        self.assertEqual(invoice(9000), "450.00")


if __name__ == "__main__":
    unittest.main()
