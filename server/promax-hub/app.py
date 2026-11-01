import hashlib
import os
import secrets
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Literal

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, Field


class Pair(BaseModel):
    model_config = ConfigDict(extra="forbid")
    code: str = Field(min_length=24, max_length=128)
    account_id: int = Field(gt=0)


class Draft(BaseModel):
    model_config = ConfigDict(extra="forbid")
    text: str = Field(max_length=8000)
    revision: int = Field(ge=0)


class Publish(BaseModel):
    model_config = ConfigDict(extra="forbid")
    revision: int = Field(ge=1)


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


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


class Hub:
    def __init__(self, path):
        self.path = Path(path)
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
            """)

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
        return row[0]

    def cleanup(self):
        cutoff = int(time.time()) - 14 * 86400
        with self.db() as db:
            db.execute("DELETE FROM telemetry WHERE created < ?", (cutoff,))
            db.execute("DELETE FROM telemetry WHERE id NOT IN (SELECT id FROM telemetry ORDER BY id DESC LIMIT 100000)")
            db.execute("DELETE FROM pair_codes WHERE expires < ?", (int(time.time()),))
            db.execute("DELETE FROM rate_limits WHERE window < ?", (int(time.time()) // 3600 - 48,))


def create_app(database=None):
    hub = Hub(database or os.environ.get("PROMAX_HUB_DB", "/var/lib/promax-hub/hub.sqlite3"))
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
    app.state.hub = hub
    app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["GET", "POST", "PUT"], allow_headers=["Authorization", "Content-Type"])

    @app.middleware("http")
    async def bounded_body(request: Request, call_next):
        length = request.headers.get("content-length", "0")
        if not length.isdigit() or int(length) > 49152:
            from fastapi.responses import JSONResponse
            return JSONResponse({"detail": "body_too_large"}, status_code=413)
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    @app.get("/health")
    def health():
        return {"service": "ProMax", "status": "ok", "schema": 1}

    @app.get("/v1/announcements")
    def announcements(after: int = 0):
        if after < 0:
            raise HTTPException(422, "invalid_cursor")
        with hub.db() as db:
            if after == 0:
                rows = list(reversed(db.execute("SELECT id,text,created FROM announcements ORDER BY id DESC LIMIT 100").fetchall()))
            else:
                rows = db.execute("SELECT id,text,created FROM announcements WHERE id>? ORDER BY id LIMIT 100", (after,)).fetchall()
        return {"messages": [dict(row) for row in rows]}

    @app.post("/v1/admin/pair")
    def pair(body: Pair, request: Request):
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
            return dict(db.execute("SELECT text,revision,published_revision FROM draft WHERE id=1").fetchone())

    @app.put("/v1/admin/draft")
    def save_draft(body: Draft, authorization: str | None = Header(default=None)):
        hub.admin(authorization)
        text = body.text.strip()
        with hub.db() as db:
            changed = db.execute("UPDATE draft SET text=?,revision=revision+1 WHERE id=1 AND revision=?", (text, body.revision)).rowcount
            if changed != 1:
                raise HTTPException(409, "draft_changed")
            return dict(db.execute("SELECT text,revision,published_revision FROM draft WHERE id=1").fetchone())

    @app.post("/v1/admin/publish")
    def publish(body: Publish, authorization: str | None = Header(default=None)):
        hub.admin(authorization)
        with hub.db() as db:
            db.execute("BEGIN IMMEDIATE")
            draft = db.execute("SELECT * FROM draft WHERE id=1").fetchone()
            if body.revision != draft["revision"] or not draft["text"]:
                raise HTTPException(409, "draft_changed_or_empty")
            if draft["published_revision"] == body.revision:
                row = db.execute("SELECT id,text,created FROM announcements WHERE revision=?", (body.revision,)).fetchone()
                return dict(row)
            now = int(time.time())
            result = db.execute("INSERT INTO announcements(text,created,revision) VALUES(?,?,?)", (draft["text"], now, body.revision))
            db.execute("UPDATE draft SET published_revision=? WHERE id=1", (body.revision,))
            return {"id": result.lastrowid, "text": draft["text"], "created": now}

    @app.post("/v1/telemetry", status_code=202)
    def telemetry(body: Diagnostics, request: Request):
        import json
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

    return app
