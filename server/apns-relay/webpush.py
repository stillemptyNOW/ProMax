import base64
import hmac
import time
from urllib.parse import urlsplit

import jwt
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

MAX_VAPID_KEY = 'BAlrEY3NvC8TgHWYfNRY3LZOtrPh8fVtz5eSNqMtN-UNI75jrLjBIAFXqrk87V9FNMVkMqgDtRXlyzvvErmj-8Q'


def b64encode(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=').decode('ascii')


def b64decode(value):
    return base64.urlsafe_b64decode(value + '=' * (-len(value) % 4))


def public_bytes(key):
    return key.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)


def verify_vapid(authorization, crypto_key, base_url, expected_key=MAX_VAPID_KEY):
    if authorization.lower().startswith('vapid '):
        parameters = dict(part.strip().split('=', 1) for part in authorization[6:].split(','))
        token = parameters['t']
        key = parameters['k']
    elif authorization.lower().startswith('webpush '):
        token = authorization[8:]
        parameters = dict(part.strip().split('=', 1) for part in crypto_key.replace(';', ',').split(',') if '=' in part)
        key = parameters['p256ecdsa']
    else:
        raise ValueError('Missing VAPID authorization')
    if not hmac.compare_digest(key, expected_key):
        raise ValueError('Unknown push sender')
    public = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), b64decode(key))
    uri = urlsplit(base_url)
    audience = f'{uri.scheme}://{uri.netloc}'
    claims = jwt.decode(token, public, algorithms=['ES256'], audience=audience, options={'require': ['exp', 'aud']})
    if claims['exp'] > time.time() + 86400:
        raise ValueError('VAPID expiry exceeds 24 hours')


def decrypt_webpush(body, private_key, auth_secret):
    if not 103 <= len(body) <= 65536:
        raise ValueError('Invalid push size')
    salt = body[:16]
    record_size = int.from_bytes(body[16:20], 'big')
    key_length = body[20]
    if key_length != 65 or not 18 <= record_size <= 65536:
        raise ValueError('Invalid encrypted header')
    sender_bytes = body[21:86]
    sender = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), sender_bytes)
    shared = private_key.exchange(ec.ECDH(), sender)
    info = b'WebPush: info\x00' + public_bytes(private_key) + sender_bytes
    ikm = HKDF(algorithm=hashes.SHA256(), length=32, salt=auth_secret, info=info).derive(shared)
    key = HKDF(algorithm=hashes.SHA256(), length=16, salt=salt, info=b'Content-Encoding: aes128gcm\x00').derive(ikm)
    nonce = HKDF(algorithm=hashes.SHA256(), length=12, salt=salt, info=b'Content-Encoding: nonce\x00').derive(ikm)
    encrypted = body[86:]
    decoded = bytearray()
    for sequence, offset in enumerate(range(0, len(encrypted), record_size)):
        record = encrypted[offset:offset + record_size]
        record_nonce = (int.from_bytes(nonce, 'big') ^ sequence).to_bytes(12, 'big')
        clear = AESGCM(key).decrypt(record_nonce, record, None).rstrip(b'\x00')
        final = offset + record_size >= len(encrypted)
        if not clear or clear[-1] != (2 if final else 1):
            raise ValueError('Invalid record delimiter')
        decoded.extend(clear[:-1])
    return bytes(decoded)
