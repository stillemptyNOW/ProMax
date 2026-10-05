import asyncio
import hmac
import json
import os
import re
import secrets
import sqlite3
import time
from pathlib import Path
from urllib.parse import urlsplit
from contextlib import contextmanager

import httpx
import jwt
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import load_pem_private_key
from fastapi import FastAPI, HTTPException, Request, Response
from pydantic import BaseModel, Field

from webpush import b64decode, b64encode, decrypt_webpush, public_bytes, verify_vapid

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
_database_lock = asyncio.Lock()
_apns_lock = asyncio.Lock()
_provider_token = ('', 0)


def setting(name):
    value = os.environ.get(name, '').strip()
    if not value:
        raise RuntimeError(f'Missing {name}')
    return value


@contextmanager
def database():
    path = Path(os.environ.get('PROMAX_PUSH_DB', 'data/subscriptions.sqlite'))
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path)
    connection.execute('CREATE TABLE IF NOT EXISTS subscriptions (id TEXT PRIMARY KEY, token TEXT NOT NULL UNIQUE, environment TEXT NOT NULL, private_key TEXT NOT NULL, auth TEXT NOT NULL)')
    if os.name != 'nt':
        os.chmod(path, 0o600)
    try:
        with connection:
            yield connection
    finally:
        connection.close()


def require_auth(request):
    secret = setting('PROMAX_RELAY_SECRET')
    if len(secret) < 32:
        raise RuntimeError('PROMAX_RELAY_SECRET must have at least 32 characters')
    if not hmac.compare_digest(request.headers.get('authorization', ''), f'Bearer {secret}'):
        raise HTTPException(401)


def apns_configured():
    if not all(os.environ.get(name, '').strip() for name in
               ('APNS_KEY_FILE', 'APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_BUNDLE_ID')):
        return False
    if not all(re.fullmatch(r'[A-Za-z0-9]{10}', os.environ[name]) for name in
               ('APNS_KEY_ID', 'APNS_TEAM_ID')):
        return False
    try:
        private = load_pem_private_key(Path(os.environ['APNS_KEY_FILE']).read_bytes(), password=None)
        return isinstance(private, ec.EllipticCurvePrivateKey) and isinstance(private.curve, ec.SECP256R1)
    except (OSError, ValueError, TypeError):
        return False


@app.get('/health')
@app.get('/')
async def health():
    ready = apns_configured()
    return {'service': 'ProMax push', 'deliveryReady': ready,
            'status': 'configured' if ready else 'awaiting_apns',
            'message': 'Конфигурация APNs загружена; доставка требует проверки.' if ready
            else 'Сервер доступен. Отправка уведомлений ожидает настройки APNs.'}


class Registration(BaseModel):
    apnsToken: str = Field(min_length=64, max_length=512, pattern=r'^[0-9a-fA-F]+$')
    environment: str = Field(default='production', pattern=r'^(production|sandbox)$')


@app.post('/v1/subscriptions')
async def register(data: Registration, request: Request):
    require_auth(request)
    if not apns_configured():
        raise HTTPException(503, detail='apns_not_configured')
    base = setting('PROMAX_RELAY_URL').rstrip('/')
    uri = urlsplit(base)
    if uri.scheme != 'https' or not uri.hostname or uri.username or uri.query or uri.fragment or uri.path not in ('', '/'):
        raise RuntimeError('PROMAX_RELAY_URL must be an HTTPS origin')
    async with _database_lock:
        with database() as connection:
            record = connection.execute('SELECT id, private_key, auth FROM subscriptions WHERE token = ?', (data.apnsToken.lower(),)).fetchone()
            if record is None:
                private = ec.generate_private_key(ec.SECP256R1())
                record = (secrets.token_urlsafe(32), str(private.private_numbers().private_value), b64encode(secrets.token_bytes(16)))
                connection.execute('INSERT INTO subscriptions VALUES (?, ?, ?, ?, ?)', (record[0], data.apnsToken.lower(), data.environment, record[1], record[2]))
            else:
                connection.execute('UPDATE subscriptions SET environment = ? WHERE id = ?', (data.environment, record[0]))
    private = ec.derive_private_key(int(record[1]), ec.SECP256R1())
    return {'id': record[0], 'endpoint': f'{base}/webpush/{record[0]}', 'p256dh': b64encode(public_bytes(private)), 'auth': record[2]}


@app.delete('/v1/subscriptions/{subscription_id}')
async def unregister(subscription_id: str, request: Request):
    require_auth(request)
    async with _database_lock:
        with database() as connection:
            connection.execute('DELETE FROM subscriptions WHERE id = ?', (subscription_id,))
    return Response(status_code=204)


async def send_apns(token, environment, chat_id):
    global _provider_token
    async with _apns_lock:
        now = int(time.time())
        if now - _provider_token[1] > 3000:
            key = Path(setting('APNS_KEY_FILE')).read_text()
            encoded = jwt.encode({'iss': setting('APNS_TEAM_ID'), 'iat': now}, key, algorithm='ES256', headers={'kid': setting('APNS_KEY_ID')})
            _provider_token = (encoded, now)
        authorization = _provider_token[0]
    payload = {'aps': {'alert': {'title': 'ProMax', 'body': 'Новое событие в MAX'}, 'sound': 'default'}}
    if chat_id:
        payload['promax_chat'] = chat_id
    host = 'api.push.apple.com' if environment == 'production' else 'api.sandbox.push.apple.com'
    async with httpx.AsyncClient(http2=True, timeout=15) as client:
        response = await client.post(f'https://{host}/3/device/{token}', headers={
            'authorization': f'bearer {authorization}',
            'apns-topic': setting('APNS_BUNDLE_ID'),
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'apns-expiration': str(int(time.time()) + 300),
        }, json=payload)
    return response.status_code, response.json().get('reason', '') if response.content else ''


def chat_id_from_payload(payload):
    if not isinstance(payload, dict):
        return 0
    for key in ('chatId', 'chat_id', 'promax_chat'):
        value = payload.get(key)
        if isinstance(value, (str, int)) and not isinstance(value, bool) and re.fullmatch(r'-?\d{1,18}', str(value)):
            return int(value)
    for key in ('data', 'custom', 'payload'):
        result = chat_id_from_payload(payload.get(key))
        if result:
            return result
    return 0


@app.post('/webpush/{subscription_id}')
async def receive_push(subscription_id: str, request: Request):
    if request.headers.get('content-encoding', '').lower() != 'aes128gcm':
        raise HTTPException(415)
    try:
        verify_vapid(request.headers.get('authorization', ''), request.headers.get('crypto-key', ''), setting('PROMAX_RELAY_URL'))
    except (ValueError, KeyError, jwt.InvalidTokenError):
        raise HTTPException(403) from None
    if not apns_configured():
        raise HTTPException(503, detail='apns_not_configured')
    async with _database_lock:
        with database() as connection:
            record = connection.execute('SELECT token, environment, private_key, auth FROM subscriptions WHERE id = ?', (subscription_id,)).fetchone()
    if record is None:
        raise HTTPException(410)
    body = bytearray()
    async for chunk in request.stream():
        body.extend(chunk)
        if len(body) > 65536:
            raise HTTPException(413)
    try:
        private = ec.derive_private_key(int(record[2]), ec.SECP256R1())
        clear = decrypt_webpush(bytes(body), private, b64decode(record[3]))
        payload = json.loads(clear)
    except Exception:
        raise HTTPException(400) from None
    try:
        status, reason = await send_apns(record[0], record[1], chat_id_from_payload(payload))
    except (httpx.HTTPError, OSError):
        raise HTTPException(503) from None
    if status == 410 or status == 400 and reason == 'BadDeviceToken':
        async with _database_lock:
            with database() as connection:
                connection.execute('DELETE FROM subscriptions WHERE id = ?', (subscription_id,))
        raise HTTPException(410)
    if status != 200:
        raise HTTPException(503)
    return Response(status_code=201)
