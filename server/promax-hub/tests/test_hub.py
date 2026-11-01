import concurrent.futures
import tempfile
import unittest
from pathlib import Path
from fastapi.testclient import TestClient
from app import create_app


class HubTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.app = create_app(Path(self.directory.name) / "hub.db")
        self.client = TestClient(self.app)
        self.addCleanup(self.client.close)
        self.addCleanup(self.directory.cleanup)

    def admin(self):
        code = self.app.state.hub.issue_code()
        response = self.client.post("/v1/admin/pair", json={"code": code, "account_id": 101})
        self.assertEqual(response.status_code, 200)
        return {"Authorization": "Bearer " + response.json()["token"]}

    def test_anonymous_cannot_write_or_read_draft(self):
        self.assertEqual(self.client.get("/v1/admin/draft").status_code, 401)
        self.assertEqual(self.client.put("/v1/admin/draft", json={"text": "synthetic", "revision": 0}).status_code, 401)
        self.assertEqual(self.client.post("/v1/admin/publish", json={"revision": 1}).status_code, 401)

    def test_pairing_code_is_single_use(self):
        code = self.app.state.hub.issue_code()
        body = {"code": code, "account_id": 101}
        self.assertEqual(self.client.post("/v1/admin/pair", json=body).status_code, 200)
        self.assertEqual(self.client.post("/v1/admin/pair", json=body).status_code, 403)

    def test_draft_is_private_until_explicit_publish(self):
        headers = self.admin()
        self.client.put("/v1/admin/draft", headers=headers, json={"text": "synthetic announcement", "revision": 0})
        self.assertEqual(self.client.get("/v1/announcements").json()["messages"], [])
        self.assertEqual(self.client.get("/v1/admin/draft", headers=headers).json()["revision"], 1)
        response = self.client.post("/v1/admin/publish", headers=headers, json={"revision": 1})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.client.get("/v1/announcements").json()["messages"][0]["text"], "synthetic announcement")

    def test_publish_retries_do_not_duplicate_messages(self):
        headers = self.admin()
        self.client.put("/v1/admin/draft", headers=headers, json={"text": "synthetic", "revision": 0})
        def publish(_):
            return self.client.post("/v1/admin/publish", headers=headers, json={"revision": 1}).json()["id"]
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            ids = list(executor.map(publish, range(8)))
        self.assertEqual(len(set(ids)), 1)
        self.assertEqual(len(self.client.get("/v1/announcements").json()["messages"]), 1)

    def test_stale_draft_cannot_overwrite_or_publish(self):
        headers = self.admin()
        self.client.put("/v1/admin/draft", headers=headers, json={"text": "synthetic", "revision": 0})
        self.assertEqual(self.client.put("/v1/admin/draft", headers=headers, json={"text": "old", "revision": 0}).status_code, 409)
        self.assertEqual(self.client.post("/v1/admin/publish", headers=headers, json={"revision": 2}).status_code, 409)

    def test_web_client_can_use_public_api_and_bearer_preflight(self):
        response = self.client.options("/v1/admin/draft", headers={
            "Origin": "https://synthetic.example", "Access-Control-Request-Method": "PUT",
            "Access-Control-Request-Headers": "authorization,content-type"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["access-control-allow-origin"], "*")
        self.assertEqual(self.client.get("/v1/admin/draft").status_code, 401)

    def test_telemetry_rejects_private_fields(self):
        event = {"kind": "flutter_error", "error_type": "StateError", "frames": ["package:promax/main.dart:12:3"], "version": "1.1.0+120", "platform": "android"}
        body = {"installation": "a" * 48, "events": [event]}
        self.assertEqual(self.client.post("/v1/telemetry", json=body).status_code, 202)
        event["text"] = "synthetic private text"
        self.assertEqual(self.client.post("/v1/telemetry", json=body).status_code, 422)
        del event["text"]
        event["frames"] = ["/home/synthetic-user/secret"]
        self.assertEqual(self.client.post("/v1/telemetry", json=body).status_code, 422)


if __name__ == "__main__":
    unittest.main()
