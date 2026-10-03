import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

import jwt
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient

from webpush import b64decode, b64encode, decrypt_webpush, public_bytes, verify_vapid
from app import app, chat_id_from_payload


class WebPushTests(unittest.TestCase):
    def setUp(self):
        self.private = ec.derive_private_key(int.from_bytes(b64decode('q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94'), 'big'), ec.SECP256R1())
        self.auth = b64decode('BTBZMqHH6r4Tts7J_aSIgg')
        header = 'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8'
        cipher = '8pfeW0KbunFT06SuDKoJH9Ql87S1QUrdirN6GcG7sFz1y1sqLgVi1VhjVkHsUoEsbI_0LpXMuGvnzQ'
        self.body = b64decode(header) + b64decode(cipher)

    def test_rfc8291_interoperability_vector(self):
        self.assertEqual(decrypt_webpush(self.body, self.private, self.auth), b'When I grow up, I want to be a watermelon')

    def test_modified_ciphertext_is_rejected(self):
        body = bytearray(self.body)
        body[-1] ^= 1
        with self.assertRaises(InvalidTag):
            decrypt_webpush(bytes(body), self.private, self.auth)

    def test_truncated_payload_is_rejected(self):
        with self.assertRaises(ValueError):
            decrypt_webpush(self.body[:50], self.private, self.auth)

    def test_sender_signature_and_audience_are_required(self):
        sender = ec.generate_private_key(ec.SECP256R1())
        public = b64encode(public_bytes(sender))
        token = jwt.encode({'aud': 'https://push.example.test', 'exp': int(time.time()) + 60}, sender, algorithm='ES256')
        authorization = f'vapid t={token}, k={public}'
        verify_vapid(authorization, '', 'https://push.example.test', expected_key=public)
        with self.assertRaises(ValueError):
            verify_vapid(authorization, '', 'https://push.example.test')
        with self.assertRaises(jwt.InvalidAudienceError):
            verify_vapid(authorization, '', 'https://other.example.test', expected_key=public)

    def test_negative_group_id_is_preserved_without_message_text(self):
        self.assertEqual(chat_id_from_payload({'data': {'chatId': '-101', 'text': 'Synthetic secret'}}), -101)
        self.assertEqual(chat_id_from_payload({'chatId': True}), 0)

    def test_registration_requires_access_key_and_can_be_revoked(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict('os.environ', {
            'PROMAX_RELAY_SECRET': 'synthetic-access-key-0000000000000000',
            'PROMAX_RELAY_URL': 'https://push.example.test',
            'PROMAX_PUSH_DB': str(Path(directory) / 'subscriptions.sqlite'),
        }):
            with TestClient(app) as client:
                registration = {'apnsToken': 'ab' * 32, 'environment': 'production'}
                self.assertEqual(client.post('/v1/subscriptions', json=registration).status_code, 401)
                headers = {'Authorization': 'Bearer synthetic-access-key-0000000000000000'}
                result = client.post('/v1/subscriptions', headers=headers, json=registration)
                self.assertEqual(result.status_code, 200)
                record = result.json()
                self.assertEqual(len(b64decode(record['p256dh'])), 65)
                self.assertEqual(len(b64decode(record['auth'])), 16)
                again = client.post('/v1/subscriptions', headers=headers, json=registration)
                self.assertEqual(again.json()['id'], record['id'])
                self.assertEqual(client.delete(f"/v1/subscriptions/{record['id']}", headers=headers).status_code, 204)


if __name__ == '__main__':
    unittest.main()
