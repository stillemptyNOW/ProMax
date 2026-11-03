import hashlib
import hmac
import json
import os
import re
import secrets
import time
from pathlib import Path
from typing import Literal
from urllib.parse import parse_qsl

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field


class MiniAppIdentity:
    def __init__(self, token, bot_id):
        self.token = token
        self.bot_id = bot_id

    @classmethod
    def configured(cls):
        path = os.environ.get("PROMAX_MAX_BOT_TOKEN_FILE", "/etc/promax-hub/max-bot.token")
        try:
            token = Path(path).read_text().strip()
        except FileNotFoundError:
            token = ""
        return cls(token, int(os.environ.get("PROMAX_MAX_BOT_ID", "0")))

    @property
    def ready(self):
        return bool(self.token) and self.bot_id > 0

    def verify(self, raw):
        if not self.ready:
            raise HTTPException(503, "identity_not_configured")
        try:
            if re.search(r"%(?![0-9a-fA-F]{2})", raw):
                raise ValueError()
            pairs = parse_qsl(raw, keep_blank_values=True, strict_parsing=True, encoding="utf-8", errors="strict", max_num_fields=20)
            values = dict(pairs)
            if len(values) != len(pairs):
                raise ValueError()
            supplied = values.pop("hash")
            if not re.fullmatch(r"[a-f0-9]{64}", supplied):
                raise ValueError()
            date = int(values["auth_date"])
            if date < int(time.time()) - 120 or date > int(time.time()) + 15:
                raise ValueError()
            secret = hmac.digest(b"WebAppData", self.token.encode(), "sha256")
            data = "\n".join(f"{key}={values[key]}" for key in sorted(values)).encode()
            expected = hmac.new(secret, data, "sha256").hexdigest()
            if not hmac.compare_digest(expected, supplied):
                raise ValueError()
            user = json.loads(values["user"])
            account = user["id"]
            if type(account) is not int or account <= 0 or account > 9223372036854775807:
                raise ValueError()
            return account, supplied
        except (ValueError, TypeError, KeyError, UnicodeError):
            raise HTTPException(401, "invalid_identity_proof")


class IdentityProof(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    init_data: str = Field(min_length=1, max_length=12000)


class SocialConsent(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    show_os: bool = False
    show_promax: bool = False
    allow_groups: bool = False
    share_wallpaper: bool = False


class Pulse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    os: Literal["android", "ios", "windows", "macos", "linux", "web"]


class PeerQuery(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    accounts: list[int] = Field(max_length=100)


def social_routes(hub, identity):
    router = APIRouter()
    with hub.db() as db:
        db.executescript("""
            CREATE TABLE IF NOT EXISTS social_members(account INTEGER PRIMARY KEY, show_os INTEGER NOT NULL DEFAULT 0, show_promax INTEGER NOT NULL DEFAULT 0, allow_groups INTEGER NOT NULL DEFAULT 0, share_wallpaper INTEGER NOT NULL DEFAULT 0, os TEXT, seen INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS social_sessions(digest TEXT PRIMARY KEY, account INTEGER NOT NULL, expires INTEGER NOT NULL);
            CREATE INDEX IF NOT EXISTS social_sessions_account ON social_sessions(account);
            CREATE TABLE IF NOT EXISTS social_proofs(digest TEXT PRIMARY KEY, expires INTEGER NOT NULL);
        """)

    def token_digest(token):
        return hashlib.sha256(token.encode()).hexdigest()

    def authenticated(authorization):
        if not authorization or not authorization.startswith("Bearer ") or len(authorization) > 160:
            raise HTTPException(401, "identity_required")
        digest = token_digest(authorization[7:])
        with hub.db() as db:
            row = db.execute("SELECT account FROM social_sessions WHERE digest=? AND expires>?", (digest, int(time.time()))).fetchone()
        if row is None:
            raise HTTPException(401, "identity_required")
        return row[0]

    def consent(row):
        return {key: bool(row[key]) for key in ("show_os", "show_promax", "allow_groups", "share_wallpaper")}

    @router.get("/v1/identity/config")
    def configuration():
        return {"ready": identity.ready, "bot_id": identity.bot_id if identity.ready else None}

    @router.post("/v1/identity/session")
    def session(body: IdentityProof):
        account, proof = identity.verify(body.init_data)
        hub.limit("social_session:" + str(account), 10, 3600)
        now = int(time.time())
        token = secrets.token_urlsafe(48)
        with hub.db() as db:
            db.execute("BEGIN IMMEDIATE")
            db.execute("DELETE FROM social_proofs WHERE expires<?", (now,))
            if db.execute("SELECT 1 FROM social_proofs WHERE digest=?", (proof,)).fetchone():
                raise HTTPException(401, "identity_proof_already_used")
            db.execute("INSERT INTO social_proofs VALUES(?,?)", (proof, now + 180))
            db.execute("INSERT OR IGNORE INTO social_members(account) VALUES(?)", (account,))
            db.execute("DELETE FROM social_sessions WHERE expires<?", (now,))
            db.execute("INSERT INTO social_sessions VALUES(?,?,?)", (token_digest(token), account, now + 30 * 86400))
        return {"token": token, "account_id": account}

    @router.get("/v1/identity/me")
    def me(authorization: str | None = Header(default=None)):
        account = authenticated(authorization)
        with hub.db() as db:
            row = db.execute("SELECT * FROM social_members WHERE account=?", (account,)).fetchone()
        return {"account_id": account, "consent": consent(row)}

    @router.put("/v1/identity/consent")
    def update_consent(body: SocialConsent, authorization: str | None = Header(default=None)):
        account = authenticated(authorization)
        with hub.db() as db:
            db.execute("UPDATE social_members SET show_os=?,show_promax=?,allow_groups=?,share_wallpaper=?,os=CASE WHEN ? THEN os ELSE NULL END,seen=CASE WHEN ? THEN seen ELSE 0 END WHERE account=?",
                       (body.show_os, body.show_promax, body.allow_groups, body.share_wallpaper, body.show_os, body.show_os, account))
        return {"consent": body.model_dump()}

    @router.post("/v1/identity/pulse")
    def pulse(body: Pulse, authorization: str | None = Header(default=None)):
        account = authenticated(authorization)
        hub.limit("social_pulse:" + str(account), 6, 60)
        with hub.db() as db:
            db.execute("UPDATE social_members SET os=?,seen=? WHERE account=? AND show_os=1", (body.os, int(time.time()), account))
        return {"ok": True}

    @router.post("/v1/peers")
    def peers(body: PeerQuery, authorization: str | None = Header(default=None)):
        account = authenticated(authorization)
        hub.limit("social_peers:" + str(account), 60, 60)
        accounts = sorted(set(value for value in body.accounts if 0 < value <= 9223372036854775807))
        if not accounts:
            return {"peers": []}
        placeholders = ",".join("?" for _ in accounts)
        now = int(time.time())
        with hub.db() as db:
            rows = db.execute(f"SELECT * FROM social_members WHERE account IN ({placeholders}) AND (show_promax=1 OR (show_os=1 AND seen>?))", (*accounts, now - 180)).fetchall()
        return {"peers": [{"account_id": row["account"], "os": row["os"] if row["show_os"] and row["seen"] > now - 180 else None,
                           "os_expires": row["seen"] + 180 if row["show_os"] else 0, "promax": bool(row["show_promax"]),
                           "allow_groups": bool(row["allow_groups"] and row["show_promax"])} for row in rows]}

    @router.delete("/v1/identity/me")
    def delete_me(authorization: str | None = Header(default=None)):
        account = authenticated(authorization)
        with hub.db() as db:
            db.execute("DELETE FROM social_sessions WHERE account=?", (account,))
            db.execute("DELETE FROM social_members WHERE account=?", (account,))
            db.execute("DELETE FROM rate_limits WHERE key IN (?,?,?)", tuple(prefix + str(account) for prefix in ("social_session:", "social_pulse:", "social_peers:")))
        return {"deleted": True}

    return router
