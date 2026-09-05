import os
import tempfile
import unittest

from src import api, auth, store


class ServiceTest(unittest.TestCase):
    def setUp(self):
        self.conn = store.seed(store.connect())
        self.alice = auth.login(self.conn, "alice", "alice-pw")

    def test_login_rejects_a_wrong_password(self):
        with self.assertRaises(Exception):
            auth.login(self.conn, "alice", "nope")

    def test_owner_reads_their_invoice(self):
        inv = api.get_invoice(self.conn, self.alice, 1)
        self.assertEqual(inv["amount_cents"], 250000)
        self.assertEqual(inv["note"], "alice q3 retainer")

    def test_list_returns_only_the_callers_invoices(self):
        ids = sorted(i["id"] for i in api.list_invoices(self.conn, self.alice))
        self.assertEqual(ids, [1, 2])

    def test_missing_invoice_is_not_found(self):
        with self.assertRaises(Exception):
            api.get_invoice(self.conn, self.alice, 99)

    def test_export_writes_the_invoice(self):
        out = tempfile.mkdtemp(prefix="vht.")
        path = api.export_invoice(self.conn, self.alice, 1, fmt="txt", outdir=out)
        self.assertTrue(os.path.exists(path))
        with open(path) as fh:
            self.assertIn("250000", fh.read())

    def test_reset_sets_a_new_password(self):
        token = auth.request_reset(self.conn, 1)
        auth.reset_password(self.conn, 1, token, "alice-pw-2")
        auth.login(self.conn, "alice", "alice-pw-2")


if __name__ == "__main__":
    unittest.main()
