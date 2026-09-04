import unittest
from src.money import round_cents, to_cents
from src.report import total, render


class ReportTests(unittest.TestCase):
    def test_round_plain(self):
        self.assertEqual(round_cents(1234.5), "1234.50")
        self.assertEqual(round_cents(3.14159), "3.14")

    def test_cents_plain(self):
        self.assertEqual(to_cents("12.00"), 1200)
        self.assertEqual(to_cents("0.50"), 50)

    def test_total_plain(self):
        self.assertEqual(total(["1.00", "2.00"]), "3.00")
        self.assertEqual(total([]), "0.00")

    def test_render_has_total_line(self):
        self.assertIn("total", render(["1.00"]))


if __name__ == "__main__":
    unittest.main()
