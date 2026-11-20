import hashlib
import json
import os
import secrets
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Literal

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, ConfigDict, Field, ValidationError, model_validator
from releases import ReleaseCatalog
from request_body import read_bounded_body
from settings_links import LINK_CODE, LINK_LIFETIME, MAX_LINKS, parse_settings_link


class Pair(BaseModel):
    model_config = ConfigDict(extra="forbid")
    code: str = Field(min_length=24, max_length=128)
    account_id: int = Field(gt=0)


KINDS = ("news", "update", "important", "promo", "holiday")
ACTIONS = ("link", "update", "settings")


class Draft(BaseModel):
    model_config = ConfigDict(extra="forbid")
    text: str = Field(max_length=8000)
    revision: int = Field(ge=0)
    kind: str = Field(default="news", pattern="^(news|update|important|promo|holiday)$")
    title: str = Field(default="", max_length=120)
    image: str = Field(default="", max_length=500, pattern="^(https://[^\\s]*)?$")
    button_label: str = Field(default="", max_length=40)
    button_action: str = Field(default="link", pattern="^(link|update|settings)$")
    button_url: str = Field(default="", max_length=500, pattern="^(https://[^\\s]*)?$")


class Publish(BaseModel):
    model_config = ConfigDict(extra="forbid")
    revision: int = Field(ge=1)


class DownloadClick(BaseModel):
    model_config = ConfigDict(extra="forbid")
    event: str = Field(pattern=r"^[a-f0-9]{32}$")
    asset: str = Field(min_length=1, max_length=1024)


class Diagnostic(BaseModel):
    model_config = ConfigDict(extra="forbid")
    kind: Literal["flutter_error", "uncaught_error", "log_error"]
    error_type: str = Field(min_length=1, max_length=100, pattern=r"^[A-Za-z0-9_<>,? .]+$")
    frames: list[str] = Field(max_length=16)
    version: str = Field(max_length=40, pattern=r"^[0-9A-Za-z.+_-]+$")
    platform: Literal["android", "ios", "windows", "linux", "macos", "fuchsia", "web"]


class Diagnostics(BaseModel):
    model_config = ConfigDict(extra="forbid")
    installation: str = Field(min_length=32, max_length=64, pattern=r"^[a-f0-9]+$")
    events: list[Diagnostic] = Field(min_length=1, max_length=16)


OperationStage = Literal[
    "digitalIdLaunch", "digitalIdCallback", "digitalIdExchange", "digitalIdWebView",
    "digitalIdDocuments", "digitalIdVerification", "apnsPermission", "apnsToken",
    "apnsRegistration", "apnsUnregistration", "apnsDelivery", "apnsLocalTest",
    "apnsRelayHealth", "hubRequest", "maxConnection", "webPushAuth",
    "webPushLink", "webPushReceipt", "webPushSubscription",
]
OperationOutcome = Literal[
    "started", "success", "failed", "timeout", "denied", "cancelled", "skipped",
    "invalid", "unavailable", "retry", "offline",
]
OPERATIONS_PATH = "/v1/telemetry/operations"


class OperationEvent(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    stage: OperationStage
    outcome: OperationOutcome
    duration_ms: int | None = Field(default=None, ge=0, le=3600000)
    status_code: int | None = Field(default=None, ge=100, le=599)
    version: str = Field(max_length=40, pattern=r"^(unknown|[0-9]{1,5}\.[0-9]{1,5}\.[0-9]{1,5}(?:\+[0-9]{0,10})?)$")
    platform: Literal["android", "ios", "windows", "linux", "macos", "fuchsia", "web"]


class Operations(BaseModel):
    model_config = ConfigDict(extra="forbid")
    events: list[OperationEvent] = Field(min_length=1, max_length=16)


async def parse_operations(request: Request):
    data = await read_bounded_body(request, 8192)
    try:
        return Operations.model_validate_json(data)
    except ValidationError:
        raise HTTPException(422, "invalid_operations") from None


class FrameSummary(BaseModel):
    model_config = ConfigDict(extra="forbid")
    frames: int = Field(gt=0, le=2000000000)
    slow: int = Field(ge=0, le=2000000000)
    mean_build_us: int = Field(ge=0, le=60000000)
    mean_raster_us: int = Field(ge=0, le=60000000)
    max_build_us: int = Field(ge=0, le=60000000)
    max_raster_us: int = Field(ge=0, le=60000000)

    @model_validator(mode="after")
    def validate_counts(self):
        if self.slow > self.frames or self.mean_build_us > self.max_build_us or self.mean_raster_us > self.max_raster_us:
            raise ValueError("invalid_frame_summary")
        return self


class PerformanceReport(BaseModel):
    model_config = ConfigDict(extra="forbid")
    installation: str = Field(min_length=32, max_length=64, pattern=r"^[a-f0-9]+$")
    version: str = Field(max_length=40, pattern=r"^[0-9A-Za-z.+_-]+$")
    platform: Literal["android", "ios", "windows", "linux", "macos", "fuchsia", "web"]
    mode: Literal["auto", "smooth", "beauty"]
    tier: Literal["low", "mid", "high"]
    refresh_hz: int = Field(ge=30, le=1000)
    summary: FrameSummary


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


META_COLUMNS = (("kind", "news"), ("title", ""), ("image", ""), ("button_label", ""), ("button_action", "link"), ("button_url", ""))
META_SQL = ",".join(name for name, _ in META_COLUMNS)


class Hub:
    def __init__(self, path, admin_account_id=None):
        self.path = Path(path)
        self.owner_id = admin_account_id if admin_account_id is not None else int(os.environ.get("PROMAX_ADMIN_ACCOUNT_ID", "461448957"))
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.db() as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS pair_codes(digest TEXT PRIMARY KEY, expires INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS admins(digest TEXT PRIMARY KEY, account_id INTEGER NOT NULL, created INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS draft(id INTEGER PRIMARY KEY CHECK(id=1), text TEXT NOT NULL DEFAULT '', revision INTEGER NOT NULL DEFAULT 0, published_revision INTEGER NOT NULL DEFAULT 0);
                INSERT OR IGNORE INTO draft(id) VALUES(1);
                CREATE TABLE IF NOT EXISTS announcements(id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL, created INTEGER NOT NULL, revision INTEGER UNIQUE NOT NULL);
                CREATE TABLE IF NOT EXISTS telemetry(id INTEGER PRIMARY KEY, created INTEGER NOT NULL, installation TEXT NOT NULL, event TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS rate_limits(key TEXT PRIMARY KEY, window INTEGER NOT NULL, count INTEGER NOT NULL);
                CREATE INDEX IF NOT EXISTS telemetry_created ON telemetry(created);
                CREATE TABLE IF NOT EXISTS download_total(id INTEGER PRIMARY KEY CHECK(id=1), started INTEGER NOT NULL);
                INSERT OR IGNORE INTO download_total VALUES(1, 1);
                CREATE TABLE IF NOT EXISTS download_clicks(event TEXT PRIMARY KEY, created INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS settings_links(digest TEXT PRIMARY KEY, payload TEXT NOT NULL, expires INTEGER NOT NULL);
                CREATE INDEX IF NOT EXISTS settings_links_expires ON settings_links(expires);
            """)
            for table in ("draft", "announcements"):
                have = {row[1] for row in db.execute(f"PRAGMA table_info({table})")}
                for column, default in META_COLUMNS:
                    if column not in have:
                        db.execute(f"ALTER TABLE {table} ADD COLUMN {column} TEXT NOT NULL DEFAULT '{default}'")

    @contextmanager
    def db(self):
        db = sqlite3.connect(self.path, timeout=10, isolation_level="IMMEDIATE")
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def issue_code(self):
        code = secrets.token_urlsafe(32)
        with self.db() as db:
            db.execute("DELETE FROM pair_codes")
            db.execute("INSERT INTO pair_codes VALUES(?, ?)", (digest(code), int(time.time()) + 86400))
        return code

    def limit(self, key, maximum, period):
        window = int(time.time()) // period
        with self.db() as db:
            db.execute("INSERT INTO rate_limits VALUES(?, ?, 1) ON CONFLICT(key) DO UPDATE SET window=excluded.window,count=CASE WHEN rate_limits.window=excluded.window THEN rate_limits.count+1 ELSE 1 END", (key, window))
            count = db.execute("SELECT count FROM rate_limits WHERE key=?", (key,)).fetchone()[0]
        if count > maximum:
            raise HTTPException(429, "rate_limited")

    def admin(self, authorization):
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(401, "admin_required")
        token = authorization[7:]
        if len(token) > 128:
            raise HTTPException(401, "admin_required")
        with self.db() as db:
            row = db.execute("SELECT account_id FROM admins WHERE digest=?", (digest(token),)).fetchone()
        if row is None:
            raise HTTPException(401, "admin_required")
        if row[0] != self.owner_id:
            raise HTTPException(403, "admin_account_required")
        return row[0]

    def cleanup(self):
        cutoff = int(time.time()) - 14 * 86400
        with self.db() as db:
            db.execute("DELETE FROM telemetry WHERE created < ?", (cutoff,))
            db.execute("DELETE FROM telemetry WHERE id NOT IN (SELECT id FROM telemetry ORDER BY id DESC LIMIT 100000)")
            db.execute("DELETE FROM pair_codes WHERE expires < ?", (int(time.time()),))
            db.execute("DELETE FROM rate_limits WHERE window < ?", (int(time.time()) // 3600 - 48,))
            db.execute("DELETE FROM download_clicks WHERE created < ?", (int(time.time()) - 86400,))
            db.execute("DELETE FROM settings_links WHERE expires <= ?", (int(time.time()),))

    def operation_summary(self, hours, limit, stage=None):
        cutoff = int(time.time()) - hours * 3600
        with self.db() as db:
            rows = db.execute("""
                WITH operations AS (
                    SELECT json_extract(event, '$.stage') AS stage,
                           json_extract(event, '$.outcome') AS outcome,
                           json_extract(event, '$.version') AS version,
                           json_extract(event, '$.platform') AS platform,
                           json_extract(event, '$.status_code') AS status_code,
                           json_extract(event, '$.duration_ms') AS duration_ms
                    FROM telemetry
                    WHERE created >= ? AND installation = ''
                      AND json_extract(event, '$.kind') = 'operation'
                )
                SELECT stage, outcome, version, platform, status_code, COUNT(*) AS count,
                       COUNT(duration_ms) AS timed, ROUND(AVG(duration_ms)) AS mean_duration_ms,
                       MAX(duration_ms) AS max_duration_ms
                FROM operations
                WHERE ? IS NULL OR stage = ?
                GROUP BY stage, outcome, version, platform, status_code
                ORDER BY count DESC, stage, outcome, platform, version, status_code
                LIMIT ?
            """, (cutoff, stage, stage, limit)).fetchall()
        return {"hours": hours, "limit": limit, "groups": [dict(row) for row in rows]}


def create_app(database=None, admin_account_id=None):
    hub = Hub(database or os.environ.get("PROMAX_HUB_DB", "/var/lib/promax-hub/hub.sqlite3"), admin_account_id)
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
    app.state.hub = hub
    owner_id = hub.owner_id
    catalog = ReleaseCatalog()
    app.state.catalog = catalog
    site = Path(__file__).with_name("site")
    if site.is_dir():
        app.mount("/site", StaticFiles(directory=site), name="site")
    notifications = Path(__file__).with_name("notifications")
    if not notifications.is_dir():
        notifications = Path(__file__).parent.parent / "web-push"
    if notifications.is_dir():
        app.mount("/notifications", StaticFiles(directory=notifications, html=True), name="notifications")
    app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["GET", "POST", "PUT"], allow_headers=["Authorization", "Content-Type"])

    @app.middleware("http")
    async def bounded_body(request: Request, call_next):
        length = request.headers.get("content-length", "0")
        if not length.isdigit() or int(length) > 49152:
            from fastapi.responses import JSONResponse
            return JSONResponse({"detail": "body_too_large"}, status_code=413)
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        if request.url.path.startswith("/site/"):
            response.headers["Cache-Control"] = "public, max-age=3600"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    @app.get("/push")
    def web_push_alias():
        return RedirectResponse("/notifications/")

    @app.get("/")
    def landing():
        return FileResponse(site / "index.html", headers={
            "Referrer-Policy": "strict-origin-when-cross-origin",
            "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
        })

    @app.get("/v1/releases")
    def releases():
        try:
            return catalog.get()
        except ValueError:
            raise HTTPException(503, "github_unavailable")

    @app.get("/health")
    def health():
        return {"service": "ProMax", "status": "ok", "schema": 1}

    @app.get("/v1/downloads")
    def download_count():
        with hub.db() as db:
            return {"started": db.execute("SELECT started FROM download_total WHERE id=1").fetchone()[0]}

    @app.post("/v1/downloads")
    def download_click(body: DownloadClick):
        try:
            known = any(asset["url"] == body.asset for release in catalog.get()["releases"] for asset in release["assets"])
        except ValueError:
            raise HTTPException(503, "github_unavailable")
        if not known:
            raise HTTPException(422, "unknown_asset")
        hub.limit("download_clicks", 600, 60)
        with hub.db() as db:
            db.execute("DELETE FROM download_clicks WHERE created < ?", (int(time.time()) - 86400,))
            inserted = db.execute("INSERT OR IGNORE INTO download_clicks VALUES(?, ?)", (body.event, int(time.time()))).rowcount
            if inserted:
                db.execute("UPDATE download_total SET started=started+1 WHERE id=1")
            return {"started": db.execute("SELECT started FROM download_total WHERE id=1").fetchone()[0]}

    @app.get("/settings")
    @app.get("/s")
    def settings_link():
        return FileResponse(Path(__file__).with_name("settings.html"), headers={
            "Referrer-Policy": "no-referrer",
            "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
        })

    @app.get("/settings-link.js")
    def settings_script():
        return FileResponse(Path(__file__).with_name("settings-link.js"), media_type="text/javascript")

    @app.post("/v1/settings-links", status_code=201)
    def create_settings_link(request: Request, payload: str = Depends(parse_settings_link)):
        address = request.client.host if request.client else "unknown"
        hub.limit("settings-link-ip:" + digest(address), 20, 3600)
        hub.limit("settings-link-create", 1200, 3600)
        now = int(time.time())
        code = secrets.token_urlsafe(16)
        with hub.db() as db:
            db.execute("DELETE FROM settings_links WHERE expires <= ?", (now,))
            if db.execute("SELECT count(*) FROM settings_links").fetchone()[0] >= MAX_LINKS:
                raise HTTPException(503, "settings_link_capacity")
            inserted = db.execute(
                "INSERT OR IGNORE INTO settings_links VALUES (?, ?, ?)",
                (digest(code), payload, now + LINK_LIFETIME),
            ).rowcount
            if not inserted:
                raise HTTPException(503, "settings_link_unavailable")
        return {"code": code}

    @app.get("/v1/settings-links/{code}")
    def get_settings_link(code: str):
        if not LINK_CODE.fullmatch(code):
            raise HTTPException(404, "settings_link_not_found")
        with hub.db() as db:
            row = db.execute(
                "SELECT payload FROM settings_links WHERE digest=? AND expires>?",
                (digest(code), int(time.time())),
            ).fetchone()
        if row is None:
            raise HTTPException(404, "settings_link_not_found")
        return Response(row["payload"], media_type="application/json")

    @app.get("/.well-known/assetlinks.json")
    def android_links():
        return [{"relation": ["delegate_permission/common.handle_all_urls"], "target": {
            "namespace": "android_app", "package_name": "io.github.stillemptynow.promax",
            "sha256_cert_fingerprints": ["E8:3B:E6:9E:C2:EA:9C:C8:F4:18:B5:33:63:6C:1A:11:48:24:BF:C0:5A:94:0F:CA:60:60:20:5F:39:0D:72:B6"],
        }}]

    @app.get("/v1/announcements")
    def announcements(after: int = 0):
        if after < 0:
            raise HTTPException(422, "invalid_cursor")
        with hub.db() as db:
            if after == 0:
                rows = list(reversed(db.execute("SELECT id,text,created,"+META_SQL+" FROM announcements ORDER BY id DESC LIMIT 100").fetchall()))
            else:
                rows = db.execute("SELECT id,text,created,"+META_SQL+" FROM announcements WHERE id>? ORDER BY id LIMIT 100", (after,)).fetchall()
        return {"messages": [dict(row) for row in rows]}

    @app.post("/v1/admin/pair")
    def pair(body: Pair, request: Request):
        if body.account_id != owner_id:
            raise HTTPException(403, "admin_account_required")
        address = request.client.host if request.client else "unknown"
        hub.limit("pair:" + digest(address), 8, 3600)
        token = secrets.token_urlsafe(48)
        with hub.db() as db:
            used = db.execute("DELETE FROM pair_codes WHERE digest=? AND expires>=?", (digest(body.code), int(time.time()))).rowcount
            if used != 1:
                raise HTTPException(403, "invalid_or_expired_code")
            db.execute("INSERT INTO admins VALUES(?,?,?)", (digest(token), body.account_id, int(time.time())))
        return {"token": token, "account_id": body.account_id}

    @app.get("/v1/admin/draft")
    def get_draft(authorization: str | None = Header(default=None)):
        hub.admin(authorization)
        with hub.db() as db:
            return dict(db.execute("SELECT text,revision,published_revision,"+META_SQL+" FROM draft WHERE id=1").fetchone())

    @app.put("/v1/admin/draft")
    def save_draft(body: Draft, authorization: str | None = Header(default=None)):
        hub.admin(authorization)
        text = body.text.strip()
        with hub.db() as db:
            changed = db.execute(
                "UPDATE draft SET text=?,kind=?,title=?,image=?,button_label=?,button_action=?,button_url=?,revision=revision+1 WHERE id=1 AND revision=?",
                (text, body.kind, body.title.strip(), body.image, body.button_label.strip(), body.button_action, body.button_url, body.revision),
            ).rowcount
            if changed != 1:
                raise HTTPException(409, "draft_changed")
            return dict(db.execute("SELECT text,revision,published_revision,"+META_SQL+" FROM draft WHERE id=1").fetchone())

    @app.post("/v1/admin/publish")
    def publish(body: Publish, authorization: str | None = Header(default=None)):
        hub.admin(authorization)
        with hub.db() as db:
            db.execute("BEGIN IMMEDIATE")
            draft = db.execute("SELECT * FROM draft WHERE id=1").fetchone()
            if body.revision != draft["revision"] or not draft["text"]:
                raise HTTPException(409, "draft_changed_or_empty")
            if draft["published_revision"] == body.revision:
                row = db.execute("SELECT id,text,created,"+META_SQL+" FROM announcements WHERE revision=?", (body.revision,)).fetchone()
                return dict(row)
            now = int(time.time())
            meta = {name: draft[name] for name, _ in META_COLUMNS}
            result = db.execute(
                "INSERT INTO announcements(text,created,revision," + META_SQL + ") VALUES(?,?,?," + ",".join("?" * len(meta)) + ")",
                (draft["text"], now, body.revision, *meta.values()),
            )
            db.execute("UPDATE draft SET published_revision=? WHERE id=1", (body.revision,))
            return {"id": result.lastrowid, "text": draft["text"], "created": now, **meta}

    @app.post("/v1/telemetry", status_code=202)
    def telemetry(body: Diagnostics, request: Request):
        address = request.client.host if request.client else "unknown"
        hub.limit("telemetry-ip:" + digest(address), 120, 3600)
        hub.limit("telemetry-install:" + body.installation, 20, 3600)
        events = []
        for event in body.events:
            for frame in event.frames:
                if len(frame) > 300 or not frame.startswith(("package:promax/", "package:promax_effects/", "package:promax_crypto/", "package:promax_tlottie/")) or "\n" in frame or "?" in frame or "@" in frame:
                    raise HTTPException(422, "invalid_frame")
            events.append(event.model_dump())
        with hub.db() as db:
            db.executemany("INSERT INTO telemetry(created,installation,event) VALUES(?,?,?)", [(int(time.time()), body.installation, json.dumps(event, ensure_ascii=False)) for event in events])
        hub.cleanup()
        return {"accepted": len(events)}

    @app.post(OPERATIONS_PATH, status_code=202)
    def record_operations(request: Request, body: Operations = Depends(parse_operations)):
        address = request.client.host if request.client else "unknown"
        hub.limit("operations-ip:" + digest(address), 240, 3600)
        created = int(time.time())
        events = [{"kind": "operation", **event.model_dump(exclude_none=True)} for event in body.events]
        with hub.db() as db:
            db.executemany(
                "INSERT INTO telemetry(created,installation,event) VALUES(?,'',?)",
                [(created, json.dumps(event)) for event in events],
            )
        hub.cleanup()
        return {"accepted": len(events)}

    @app.get("/v1/admin/telemetry/operations")
    def operation_summary(
        request: Request,
        authorization: str | None = Header(default=None),
        hours: int = Query(default=24, ge=1, le=336),
        limit: int = Query(default=200, ge=1, le=2000),
        stage: OperationStage | None = None,
    ):
        hub.admin(authorization)
        address = request.client.host if request.client else "unknown"
        hub.limit("operations-summary-ip:" + digest(address), 60, 3600)
        return hub.operation_summary(hours, limit, stage)

    @app.post("/v1/performance", status_code=202)
    def performance(body: PerformanceReport, request: Request):
        address = request.client.host if request.client else "unknown"
        hub.limit("performance-ip:" + digest(address), 30, 3600)
        hub.limit("performance-install:" + body.installation, 6, 3600)
        event = {"kind": "performance", **body.model_dump(exclude={"installation"})}
        with hub.db() as db:
            db.execute("INSERT INTO telemetry(created,installation,event) VALUES(?,?,?)", (int(time.time()), body.installation, json.dumps(event)))
        hub.cleanup()
        return {"accepted": 1}

    return app
