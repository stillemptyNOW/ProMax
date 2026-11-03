import hashlib
import hmac
import json
import tempfile
import time
import unittest
from pathlib import Path
from urllib.parse import urlencode

from fastapi.testclient import TestClient
from app import create_app
from social import MiniAppIdentity


class SocialTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.identity = MiniAppIdentity("synthetic-bot-token", 1001)
        self.app = create_app(Path(self.directory.name) / "hub.db", identity_provider=self.identity)
        self.client = TestClient(self.app)
        self.addCleanup(self.client.close)

    def proof(self, account=101, **extra):
        values = {"auth_date": str(int(time.time())), "query_id": "synthetic-" + str(account), "user": json.dumps({"id": account}), **extra}
        secret = hmac.digest(b"WebAppData", b"synthetic-bot-token", "sha256")
        values["hash"] = hmac.new(secret, "\n".join(f"{key}={values[key]}" for key in sorted(values)).encode(), "sha256").hexdigest()
        return urlencode(values)

    def login(self, account=101):
        response = self.client.post("/v1/identity/session", json={"init_data": self.proof(account)})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["account_id"], account)
        return {"Authorization": "Bearer " + response.json()["token"]}

    def test_forged_expired_duplicate_and_replayed_proofs_are_rejected(self):
        proof = self.proof()
        self.assertEqual(self.client.post("/v1/identity/session", json={"init_data": proof.replace("101", "202")}).status_code, 401)
        self.assertEqual(self.client.post("/v1/identity/session", json={"init_data": self.proof(auth_date="1")}).status_code, 401)
        self.assertEqual(self.client.post("/v1/identity/session", json={"init_data": proof + "&auth_date=1"}).status_code, 401)
        self.assertEqual(self.client.post("/v1/identity/session", json={"init_data": proof}).status_code, 200)
        self.assertEqual(self.client.post("/v1/identity/session", json={"init_data": proof}).status_code, 401)

    def test_disabled_configuration_fails_closed(self):
        other = create_app(Path(self.directory.name) / "disabled.db", identity_provider=MiniAppIdentity("", 0))
        with TestClient(other) as client:
            self.assertEqual(client.get("/v1/identity/config").json(), {"ready": False, "bot_id": None})
            self.assertEqual(client.post("/v1/identity/session", json={"init_data": self.proof()}).status_code, 503)

    def test_consent_defaults_off_and_hidden_matches_unknown(self):
        headers = self.login()
        self.assertEqual(self.client.post("/v1/peers", headers=headers, json={"accounts": [101, 202]}).json(), {"peers": []})
        response = self.client.get("/v1/identity/me", headers=headers)
        self.assertEqual(response.json()["consent"], {"show_os": False, "show_promax": False, "allow_groups": False, "share_wallpaper": False})
        self.assertEqual(self.client.post("/v1/peers", json={"accounts": [101]}).status_code, 401)

    def test_presence_expires_and_withdrawal_hides_all_metadata(self):
        headers = self.login()
        consent = {"show_os": True, "show_promax": True, "allow_groups": False, "share_wallpaper": False}
        self.assertEqual(self.client.put("/v1/identity/consent", headers=headers, json=consent).status_code, 200)
        self.assertEqual(self.client.post("/v1/identity/pulse", headers=headers, json={"os": "android"}).status_code, 200)
        peer = self.client.post("/v1/peers", headers=headers, json={"accounts": [101]}).json()["peers"][0]
        self.assertEqual(peer["os"], "android")
        self.assertTrue(peer["promax"])
        with self.app.state.hub.db() as db:
            db.execute("UPDATE social_members SET seen=?", (int(time.time()) - 181,))
        peer = self.client.post("/v1/peers", headers=headers, json={"accounts": [101]}).json()["peers"][0]
        self.assertIsNone(peer["os"])
        consent.update(show_os=False, show_promax=False)
        self.client.put("/v1/identity/consent", headers=headers, json=consent)
        self.assertEqual(self.client.post("/v1/peers", headers=headers, json={"accounts": [101]}).json(), {"peers": []})

    def test_delete_removes_account_tokens_and_consents(self):
        headers = self.login()
        self.assertEqual(self.client.delete("/v1/identity/me", headers=headers).status_code, 200)
        self.assertEqual(self.client.get("/v1/identity/me", headers=headers).status_code, 401)
        with self.app.state.hub.db() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM social_members").fetchone()[0], 0)
            self.assertEqual(db.execute("SELECT count(*) FROM social_sessions").fetchone()[0], 0)
