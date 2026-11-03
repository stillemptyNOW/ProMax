import unittest

from releases import REPOSITORY, ReleaseCatalog, public_releases


def release(tag="v1.1.0+121-beta.13", beta=True):
    return {"tag_name": tag, "name": "Synthetic release", "prerelease": beta, "html_url": REPOSITORY + "/releases/tag/" + tag,
            "body": "## Synthetic notes", "assets": [
                {"name": "ProMax-1.1.0-promax-universal.apk", "size": 123, "browser_download_url": REPOSITORY + "/releases/download/" + tag + "/synthetic.apk", "digest": "sha256:" + "a" * 64},
                {"name": "ProMax-1.1.0-preview-universal.apk", "size": 123, "browser_download_url": REPOSITORY + "/releases/download/" + tag + "/preview.apk"}]}


class ReleaseTests(unittest.TestCase):
    def test_excludes_debug_apks_and_preserves_checksum(self):
        catalog = public_releases([release()])
        self.assertEqual(len(catalog[0]["assets"]), 1)
        self.assertEqual(catalog[0]["assets"][0]["sha256"], "a" * 64)

    def test_sorts_by_build_and_recognizes_legacy_beta(self):
        catalog = public_releases([release("v1.1.0+119-beta.11", False), release(), release("v1.0.0+100", False)])
        self.assertEqual(catalog[0]["tag"], "v1.1.0+121-beta.13")
        self.assertTrue(catalog[1]["beta"])
        self.assertFalse(catalog[2]["beta"])

    def test_rejects_foreign_downloads_and_empty_assets(self):
        item = release()
        item["assets"][0]["browser_download_url"] = "https://synthetic.example/private.apk"
        self.assertEqual(public_releases([item])[0]["assets"], [])

    def test_caches_and_preserves_last_good_catalog_on_failure(self):
        calls = []
        now = [100]
        def fetch():
            calls.append(True)
            if len(calls) > 1:
                raise OSError("synthetic upstream failure")
            return [release()]
        catalog = ReleaseCatalog(fetch=fetch, clock=lambda: now[0])
        self.assertFalse(catalog.get()["stale"])
        self.assertEqual(catalog.get()["releases"][0]["tag"], "v1.1.0+121-beta.13")
        self.assertEqual(len(calls), 1)
        now[0] += 301
        self.assertTrue(catalog.get()["stale"])
        self.assertEqual(len(catalog.get()["releases"]), 1)
        self.assertEqual(len(calls), 2)

    def test_unavailable_upstream_without_cache_does_not_invent_releases(self):
        catalog = ReleaseCatalog(fetch=lambda: None)
        with self.assertRaises(ValueError):
            catalog.get()
