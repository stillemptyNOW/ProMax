import base64
import binascii
import hashlib
import hmac
import secrets
import time

from fastapi import APIRouter, Header, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field


CHUNK_SIZE = 24576
MAX_SIZE = 2 * 1024 * 1024
MAX_TOTAL = 64 * 1024 * 1024
LIFETIME = 30 * 86400
UPLOAD_LIFETIME = 3600


class WallpaperSize(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    size: int = Field(gt=0, le=MAX_SIZE)


class WallpaperChunk(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    data: str = Field(max_length=32768)


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def purge_expired_wallpapers(db, now):
    columns = {row[1] for row in db.execute('PRAGMA table_info(wallpaper_files)')}
    if 'created' not in columns:
        db.execute('DELETE FROM wallpaper_chunks WHERE file_id IN (SELECT id FROM wallpaper_files WHERE expires<=?)', (now,))
        db.execute('DELETE FROM wallpaper_files WHERE expires<=?', (now,))
        return
    has_deletions = db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='wallpaper_deletions'").fetchone()
    if has_deletions:
        db.execute('DELETE FROM wallpaper_deletions WHERE expires<=?', (now,))
    expired = """SELECT id FROM wallpaper_files WHERE expires<=? OR
        (created<=? AND (SELECT COALESCE(SUM(LENGTH(data)),0)
         FROM wallpaper_chunks WHERE file_id=wallpaper_files.id) != size)"""
    arguments = (now, now - UPLOAD_LIFETIME)
    db.execute(f'DELETE FROM wallpaper_chunks WHERE file_id IN ({expired})', arguments)
    db.execute(f'DELETE FROM wallpaper_files WHERE id IN ({expired})', arguments)


def wallpaper_routes(hub):
    router = APIRouter()
    with hub.db() as db:
        db.executescript("""
            CREATE TABLE IF NOT EXISTS wallpaper_files(id TEXT PRIMARY KEY, size INTEGER NOT NULL, expires INTEGER NOT NULL, read_hash TEXT NOT NULL, write_hash TEXT NOT NULL, created INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS wallpaper_chunks(file_id TEXT NOT NULL, number INTEGER NOT NULL, data BLOB NOT NULL, PRIMARY KEY(file_id,number));
            CREATE INDEX IF NOT EXISTS wallpaper_expiry ON wallpaper_files(expires);
            CREATE TABLE IF NOT EXISTS wallpaper_deletions(id TEXT PRIMARY KEY, write_hash TEXT NOT NULL, expires INTEGER NOT NULL);
        """)
        columns = {row[1] for row in db.execute('PRAGMA table_info(wallpaper_files)')}
        if 'created' not in columns:
            db.execute('ALTER TABLE wallpaper_files ADD COLUMN created INTEGER NOT NULL DEFAULT 0')
            db.execute('UPDATE wallpaper_files SET created=? WHERE created=0', (int(time.time()),))

    def authorized(db, file_id, authorization, write=False):
        if not authorization or not authorization.startswith("Bearer ") or len(authorization) > 160:
            raise HTTPException(404, "wallpaper_unavailable")
        row = db.execute("SELECT * FROM wallpaper_files WHERE id=? AND expires>?", (file_id, int(time.time()))).fetchone()
        field = "write_hash" if write else "read_hash"
        if row is None or not hmac.compare_digest(row[field], digest(authorization[7:])):
            raise HTTPException(404, "wallpaper_unavailable")
        return row

    def complete(db, row):
        total = db.execute("SELECT COUNT(*),COALESCE(SUM(LENGTH(data)),0) FROM wallpaper_chunks WHERE file_id=?", (row['id'],)).fetchone()
        return total[0] == (row['size'] + CHUNK_SIZE - 1) // CHUNK_SIZE and total[1] == row['size']

    @router.post('/v1/wallpapers', status_code=201)
    def create(body: WallpaperSize, request: Request):
        address = request.client.host if request.client else 'unknown'
        hub.limit('wallpaper-create:' + digest(address), 20, 3600)
        file_id = secrets.token_hex(16)
        read_token = secrets.token_urlsafe(32)
        write_token = secrets.token_urlsafe(32)
        expires = int(time.time()) + LIFETIME
        with hub.db() as db:
            db.execute('BEGIN IMMEDIATE')
            now = int(time.time())
            purge_expired_wallpapers(db, now)
            used = db.execute('SELECT COALESCE(SUM(size),0) FROM wallpaper_files').fetchone()[0]
            if used + body.size > MAX_TOTAL:
                raise HTTPException(503, 'wallpaper_storage_full')
            db.execute('INSERT INTO wallpaper_files(id,size,expires,read_hash,write_hash,created) VALUES(?,?,?,?,?,?)', (file_id, body.size, expires, digest(read_token), digest(write_token), now))
        return {'id': file_id, 'read_token': read_token, 'write_token': write_token, 'chunk_size': CHUNK_SIZE, 'expires': expires}

    @router.put('/v1/wallpapers/{file_id}/{number}')
    def upload(file_id: str, number: int, body: WallpaperChunk, authorization: str | None = Header(default=None)):
        with hub.db() as db:
            db.execute('BEGIN IMMEDIATE')
            row = authorized(db, file_id, authorization, write=True)
            count = (row['size'] + CHUNK_SIZE - 1) // CHUNK_SIZE
            if number < 0 or number >= count:
                raise HTTPException(404, 'wallpaper_unavailable')
            try:
                data = base64.b64decode(body.data, validate=True)
            except (ValueError, binascii.Error):
                raise HTTPException(422, 'invalid_chunk')
            expected = min(CHUNK_SIZE, row['size'] - number * CHUNK_SIZE)
            if len(data) != expected:
                raise HTTPException(422, 'invalid_chunk_size')
            existing = db.execute('SELECT data FROM wallpaper_chunks WHERE file_id=? AND number=?', (file_id, number)).fetchone()
            if existing is not None and existing[0] != data:
                raise HTTPException(409, 'chunk_conflict')
            db.execute('INSERT OR IGNORE INTO wallpaper_chunks VALUES(?,?,?)', (file_id, number, data))
        return {'stored': True}

    @router.get('/v1/wallpapers/{file_id}')
    def info(file_id: str, authorization: str | None = Header(default=None)):
        with hub.db() as db:
            row = authorized(db, file_id, authorization)
            if not complete(db, row):
                raise HTTPException(409, 'wallpaper_incomplete')
            return {'size': row['size'], 'chunk_size': CHUNK_SIZE, 'expires': row['expires']}

    @router.get('/v1/wallpapers/{file_id}/{number}')
    def download(file_id: str, number: int, authorization: str | None = Header(default=None)):
        with hub.db() as db:
            row = authorized(db, file_id, authorization)
            if not complete(db, row):
                raise HTTPException(409, 'wallpaper_incomplete')
            chunk = db.execute('SELECT data FROM wallpaper_chunks WHERE file_id=? AND number=?', (file_id, number)).fetchone()
            if chunk is None:
                raise HTTPException(404, 'wallpaper_unavailable')
            return {'data': base64.b64encode(chunk[0]).decode()}

    @router.delete('/v1/wallpapers/{file_id}')
    def delete(file_id: str, authorization: str | None = Header(default=None)):
        with hub.db() as db:
            db.execute('BEGIN IMMEDIATE')
            try:
                row = authorized(db, file_id, authorization, write=True)
            except HTTPException:
                previous = db.execute('SELECT write_hash FROM wallpaper_deletions WHERE id=? AND expires>?', (file_id, int(time.time()))).fetchone()
                if not authorization or not authorization.startswith('Bearer ') or len(authorization) > 160 or previous is None or not hmac.compare_digest(previous['write_hash'], digest(authorization[7:])):
                    raise HTTPException(404, 'wallpaper_unavailable')
                return {'deleted': True}
            db.execute('INSERT OR REPLACE INTO wallpaper_deletions VALUES(?,?,?)', (file_id, row['write_hash'], row['expires']))
            db.execute('DELETE FROM wallpaper_chunks WHERE file_id=?', (file_id,))
            db.execute('DELETE FROM wallpaper_files WHERE id=?', (file_id,))
        return {'deleted': True}

    return router
