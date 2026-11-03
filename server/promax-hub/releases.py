import json
import re
import threading
import time
import urllib.request
from urllib.parse import urlparse


REPOSITORY = "https://github.com/stillemptyNOW/ProMax"
API = "https://api.github.com/repos/stillemptyNOW/ProMax/releases?per_page=20"


def fetch_releases():
    request = urllib.request.Request(API, headers={"User-Agent": "ProMax-Downloads", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=10) as response:
        raw = response.read(2 * 1024 * 1024 + 1)
    if len(raw) > 2 * 1024 * 1024:
        raise ValueError("release_catalog_too_large")
    return json.loads(raw)


def release_version(tag):
    match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?(?:[-.](?:alpha|beta|rc|preview)[.-]?\d*)?", tag, re.IGNORECASE)
    return tuple(int(value or 0) for value in match.groups()) if match else None


def public_releases(raw):
    if not isinstance(raw, list):
        raise ValueError("invalid_release_catalog")
    releases = []
    for item in raw:
        if not isinstance(item, dict) or item.get("draft"):
            continue
        tag = item.get("tag_name", "")
        version = release_version(tag)
        if version is None:
            continue
        url = item.get("html_url", "")
        if not url.startswith(REPOSITORY + "/releases/tag/"):
            continue
        assets = []
        for asset in item.get("assets", []):
            name = asset.get("name", "")
            if "preview" in name.lower() or not name.startswith("ProMax-"):
                continue
            if not re.search(r"(?:-promax-(?:arm64-v8a|armeabi-v7a|x86_64|universal)\.apk|-ios-unsigned\.ipa|-Setup-[\d.-]+\.exe|-windows-x64\.zip|-linux-x64\.tar\.gz|-macos[^/]*\.(?:zip|dmg))$", name):
                continue
            download = asset.get("browser_download_url", "")
            parsed = urlparse(download)
            if parsed.scheme != "https" or parsed.netloc != "github.com" or not parsed.path.startswith("/stillemptyNOW/ProMax/releases/download/") or parsed.query or parsed.fragment:
                continue
            size = asset.get("size", 0)
            if not isinstance(size, int) or size <= 0:
                continue
            digest = asset.get("digest", "") or ""
            assets.append({"name": name, "url": download, "size": size,
                           "sha256": digest[7:] if re.fullmatch(r"sha256:[a-fA-F0-9]{64}", digest) else ""})
        releases.append({"tag": tag, "name": item.get("name") or tag, "url": url,
                         "beta": bool(item.get("prerelease")) or bool(re.search(r"(?:alpha|beta|rc|preview)", tag, re.IGNORECASE)),
                         "published": item.get("published_at", ""), "notes": (item.get("body") or "")[:30000],
                         "assets": assets, "version": version})
    releases.sort(key=lambda release: release["version"], reverse=True)
    for release in releases:
        del release["version"]
    return releases


class ReleaseCatalog:
    def __init__(self, fetch=fetch_releases, clock=time.monotonic):
        self.fetch = fetch
        self.clock = clock
        self.cached = None
        self.expires = 0
        self.stale = False
        self.lock = threading.Lock()

    def get(self):
        with self.lock:
            now = self.clock()
            if now >= self.expires:
                try:
                    self.cached = public_releases(self.fetch())
                    self.stale = False
                    self.expires = now + 300
                except Exception:
                    self.stale = True
                    self.expires = now + 30
            if self.cached is None:
                raise ValueError("github_unavailable")
            return {"releases": self.cached, "stale": self.stale, "source": REPOSITORY + "/releases"}
