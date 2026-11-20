import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from app import create_app


class SettingsLinkTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.database = Path(directory.name) / "hub.db"
        app = create_app(self.database, admin_account_id=101)
        self.hub = app.state.hub
        self.client = TestClient(app)
        self.addCleanup(self.client.close)
        self.payload = {
            "format": "ProMax",
            "version": 1,
            "settings": {"app_amoled": True, "promax_quick_reaction": "🌟"},
            "platform": "ios",
            "platformSettings": {"app_native_glass": False, "app_performance_mode": "smooth"},
        }

    def test_short_link_remains_resolvable_after_restart(self):
        created = self.client.post("/v1/settings-links", json=self.payload)
        self.assertEqual(created.status_code, 201)
        code = created.json()["code"]
        self.assertRegex(code, r"^[A-Za-z0-9_-]{22}$")
        landing = self.client.get(f"/s#{code}")
        self.assertEqual(landing.status_code, 200)
        self.assertNotIn(code, landing.text)
        self.assertEqual(landing.headers["referrer-policy"], "no-referrer")
        with TestClient(create_app(self.database, admin_account_id=101)) as client:
            retrieved = client.get(f"/v1/settings-links/{code}")
        self.assertEqual(retrieved.status_code, 200)
        self.assertEqual(retrieved.json(), self.payload)
        self.assertEqual(retrieved.headers["cache-control"], "no-store")

    def test_expired_links_cannot_be_resolved(self):
        code = self.client.post("/v1/settings-links", json=self.payload).json()["code"]
        with self.hub.db() as db:
            db.execute("UPDATE settings_links SET expires=0")
        self.assertEqual(self.client.get(f"/v1/settings-links/{code}").status_code, 404)
        self.hub.cleanup()
        with self.hub.db() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM settings_links").fetchone()[0], 0)

    def test_unknown_and_malformed_codes_cannot_be_resolved(self):
        for code in ("a" * 22, "too-short", "invalid*identifier12345"):
            with self.subTest(code=code):
                self.assertEqual(self.client.get(f"/v1/settings-links/{code}").status_code, 404)

    def test_invalid_or_private_fields_are_rejected(self):
        for change in (
            {"deleted": {"ciphertext": "synthetic-history"}},
            {"settings": {"auth_token_101": "synthetic-private-value"}},
            {"settings": {"app_amoled": 1}},
            {"settings": {"app_font_scale": 5}},
            {"platformSettings": {"call_pip_enabled": 1}},
            {"platform": "android"},
            {"version": True},
        ):
            with self.subTest(change=change):
                response = self.client.post("/v1/settings-links", json={**self.payload, **change})
                self.assertEqual(response.status_code, 422)
                self.assertNotIn("synthetic-private-value", response.text)

    def test_oversized_chunked_upload_is_rejected(self):
        response = self.client.post("/v1/settings-links", content=iter([b" " * 13000]))
        self.assertEqual(response.status_code, 413)
