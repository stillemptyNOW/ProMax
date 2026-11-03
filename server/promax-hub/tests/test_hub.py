import concurrent.futures
import tempfile
import unittest
from pathlib import Path
from fastapi.testclient import TestClient
from app import create_app


class HubTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.app = create_app(Path(self.directory.name) / "hub.db", admin_account_id=101)
        self.client = TestClient(self.app)
        self.addCleanup(self.client.close)
        self.addCleanup(self.directory.cleanup)

    def admin(self):
        code = self.app.state.hub.issue_code()
        response = self.client.post("/v1/admin/pair", json={"code": code, "account_id": 101})
        self.assertEqual(response.status_code, 200)
        return {"Authorization": "Bearer " + response.json()["token"]}

    def test_settings_landing_does_not_receive_or_store_fragment(self):
        response = self.client.get("/settings#v1.synthetic-settings")
        self.assertEqual(response.status_code, 200)
        self.assertIn("text/html", response.headers["content-type"])
        self.assertEqual(response.headers["referrer-policy"], "no-referrer")
        self.assertIn("frame-ancestors 'none'", response.headers["content-security-policy"])
        self.assertNotIn("synthetic-settings", response.text)
        self.assertEqual(self.client.get("/settings-link.js").status_code, 200)
        links = self.client.get("/.well-known/assetlinks.json").json()
        self.assertEqual(links[0]["target"]["package_name"], "io.github.stillemptynow.promax")

    def test_performance_report_is_bounded_and_rejects_private_fields(self):
        body = {"installation": "a" * 48, "version": "1.1.0+121", "platform": "android", "mode": "auto", "tier": "mid", "refresh_hz": 120,
                "summary": {"frames": 120, "slow": 24, "mean_build_us": 2000, "mean_raster_us": 6000, "max_build_us": 10000, "max_raster_us": 30000}}
        self.assertEqual(self.client.post("/v1/performance", json=body).status_code, 202)
        body["phone"] = "synthetic-private-value"
        self.assertEqual(self.client.post("/v1/performance", json=body).status_code, 422)
        del body["phone"]
        body["summary"]["slow"] = 121
        self.assertEqual(self.client.post("/v1/performance", json=body).status_code, 422)

    def test_anonymous_cannot_write_or_read_draft(self):
        self.assertEqual(self.client.get("/v1/admin/draft").status_code, 401)
        self.assertEqual(self.client.put("/v1/admin/draft", json={"text": "synthetic", "revision": 0}).status_code, 401)
        self.assertEqual(self.client.post("/v1/admin/publish", json={"revision": 1}).status_code, 401)

    def test_notifications_static_app_is_separate_from_download_landing(self):
        response = self.client.get("/notifications/")
        self.assertEqual(response.status_code, 200)
        self.assertIn("Уведомления MAX", response.text)
        self.assertEqual(self.client.get("/notifications/sw.js").status_code, 200)
        manifest = self.client.get("/notifications/manifest.webmanifest").json()
        self.assertEqual(manifest["scope"], "./")
        self.assertEqual(self.client.get("/notifications/../hub.sqlite3").status_code, 404)

    def test_download_count_persists_and_deduplicates_click_retries(self):
        asset = "https://github.com/stillemptyNOW/ProMax/releases/download/synthetic/ProMax-macos-universal.zip"
        self.app.state.catalog.get = lambda: {"releases": [{"assets": [{"url": asset}]}]}
        self.assertEqual(self.client.get("/v1/downloads").json(), {"started": 1})
        body = {"event": "a" * 32, "asset": asset}
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            responses = list(executor.map(lambda _: self.client.post("/v1/downloads", json=body), range(4)))
        self.assertTrue(all(response.status_code == 200 for response in responses))
        self.assertEqual(self.client.get("/v1/downloads").json(), {"started": 2})
        other = create_app(Path(self.directory.name) / "hub.db")
        with TestClient(other) as client:
            self.assertEqual(client.get("/v1/downloads").json(), {"started": 2})

    def test_unknown_download_cannot_inflate_count(self):
        self.app.state.catalog.get = lambda: {"releases": []}
        response = self.client.post("/v1/downloads", json={"event": "b" * 32, "asset": "https://synthetic.example/not-a-release.zip"})
        self.assertEqual(response.status_code, 422)
        self.assertEqual(self.client.get("/v1/downloads").json(), {"started": 1})

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

    def test_announcement_meta_defaults_and_roundtrip(self):
        headers = self.admin()
        self.client.put("/v1/admin/draft", headers=headers, json={"text": "plain", "revision": 0})
        self.client.post("/v1/admin/publish", headers=headers, json={"revision": 1})
        first = self.client.get("/v1/announcements").json()["messages"][0]
        self.assertEqual((first["kind"], first["title"], first["image"], first["button_action"]), ("news", "", "", "link"))
        rich = {"text": "**bold**", "revision": 1, "kind": "important", "title": "Synthetic title",
                "image": "https://example.test/a.png", "button_label": "Open", "button_action": "update", "button_url": ""}
        self.assertEqual(self.client.put("/v1/admin/draft", headers=headers, json=rich).json()["kind"], "important")
        self.client.post("/v1/admin/publish", headers=headers, json={"revision": 2})
        last = self.client.get("/v1/announcements?after=1").json()["messages"][0]
        self.assertEqual((last["kind"], last["title"], last["button_label"], last["button_action"]), ("important", "Synthetic title", "Open", "update"))

    def test_announcement_meta_rejects_bad_values(self):
        headers = self.admin()
        for patch in ({"kind": "other"}, {"image": "http://example.test/a.png"}, {"button_url": "javascript:alert(1)"}, {"button_action": "x"}):
            response = self.client.put("/v1/admin/draft", headers=headers, json={"text": "t", "revision": 0, **patch})
            self.assertEqual(response.status_code, 422, patch)

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
