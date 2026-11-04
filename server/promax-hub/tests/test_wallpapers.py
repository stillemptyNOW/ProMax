import base64
import tempfile
import time
import unittest
from pathlib import Path

from fastapi.testclient import TestClient
from app import create_app


class WallpaperTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = create_app(Path(self.directory.name) / "hub.db", admin_account_id=101)
        self.client = TestClient(self.app)
        self.addCleanup(self.client.close)

    def create(self, size):
        response = self.client.post('/v1/wallpapers', json={'size': size})
        self.assertEqual(response.status_code, 201)
        return response.json()

    def auth(self, token):
        return {'Authorization': 'Bearer ' + token}

    def test_chunks_are_opaque_and_require_separate_capabilities(self):
        blob = b'synthetic-encrypted-data'
        file = self.create(len(blob))
        path = '/v1/wallpapers/' + file['id']
        self.assertEqual(self.client.get(path, headers=self.auth(file['read_token'])).status_code, 409)
        body = {'data': base64.b64encode(blob).decode()}
        self.assertEqual(self.client.put(path + '/0', json=body, headers=self.auth(file['read_token'])).status_code, 404)
        self.assertEqual(self.client.put(path + '/0', json=body, headers=self.auth(file['write_token'])).status_code, 200)
        self.assertEqual(self.client.put(path + '/0', json=body, headers=self.auth(file['write_token'])).status_code, 200)
        response = self.client.get(path + '/0', headers=self.auth(file['read_token']))
        self.assertEqual(base64.b64decode(response.json()['data']), blob)
        self.assertEqual(self.client.get(path + '/0', headers=self.auth('synthetic-invalid-token')).status_code, 404)
        self.assertEqual(self.client.delete(path, headers=self.auth(file['read_token'])).status_code, 404)
        self.assertEqual(self.client.delete(path, headers=self.auth(file['write_token'])).status_code, 200)
        self.assertEqual(self.client.delete(path, headers=self.auth('synthetic-invalid-token')).status_code, 404)
        self.assertEqual(self.client.delete(path, headers=self.auth(file['write_token'])).status_code, 200)
        self.assertEqual(self.client.get(path, headers=self.auth(file['read_token'])).status_code, 404)

    def test_rejects_bad_lengths_and_conflicting_overwrites(self):
        file = self.create(4)
        path = '/v1/wallpapers/' + file['id'] + '/0'
        headers = self.auth(file['write_token'])
        self.assertEqual(self.client.put(path, json={'data': 'not-base64!'}, headers=headers).status_code, 422)
        self.assertEqual(self.client.put(path, json={'data': base64.b64encode(b'abc').decode()}, headers=headers).status_code, 422)
        self.assertEqual(self.client.put(path, json={'data': base64.b64encode(b'abcd').decode()}, headers=headers).status_code, 200)
        self.assertEqual(self.client.put(path, json={'data': base64.b64encode(b'efgh').decode()}, headers=headers).status_code, 409)
        self.assertEqual(self.client.post('/v1/wallpapers', json={'size': 2 * 1024 * 1024 + 1}).status_code, 422)

    def test_expired_files_are_inaccessible(self):
        file = self.create(4)
        with self.app.state.hub.db() as db:
            db.execute('UPDATE wallpaper_files SET expires=0')
        self.assertEqual(self.client.get('/v1/wallpapers/' + file['id'], headers=self.auth(file['read_token'])).status_code, 404)
        self.app.state.hub.cleanup()
        with self.app.state.hub.db() as db:
            self.assertEqual(db.execute('SELECT count(*) FROM wallpaper_files').fetchone()[0], 0)

    def test_incomplete_upload_reservations_expire_early(self):
        incomplete = self.create(4)
        complete = self.create(4)
        self.client.put('/v1/wallpapers/' + complete['id'] + '/0',
                        headers=self.auth(complete['write_token']),
                        json={'data': base64.b64encode(b'data').decode()})
        with self.app.state.hub.db() as db:
            db.execute('UPDATE wallpaper_files SET created=?', (int(time.time()) - 3601,))
        self.app.state.hub.cleanup()
        self.assertEqual(self.client.get('/v1/wallpapers/' + incomplete['id'], headers=self.auth(incomplete['read_token'])).status_code, 404)
        self.assertEqual(self.client.get('/v1/wallpapers/' + complete['id'], headers=self.auth(complete['read_token'])).status_code, 200)

    def test_multichunk_roundtrip_and_capabilities_are_not_stored(self):
        data = bytes(range(256)) * 96 + b'x'
        file = self.create(len(data))
        path = '/v1/wallpapers/' + file['id']
        headers = self.auth(file['write_token'])
        for number, start in enumerate(range(0, len(data), file['chunk_size'])):
            chunk = data[start:start + file['chunk_size']]
            response = self.client.put(path + '/' + str(number), headers=headers, json={'data': base64.b64encode(chunk).decode()})
            self.assertEqual(response.status_code, 200)
        recovered = b''.join(base64.b64decode(self.client.get(path + '/' + str(number), headers=self.auth(file['read_token'])).json()['data']) for number in range(2))
        self.assertEqual(recovered, data)
        with self.app.state.hub.db() as db:
            row = db.execute('SELECT read_hash,write_hash FROM wallpaper_files').fetchone()
            self.assertNotIn(file['read_token'], tuple(row))
            self.assertNotIn(file['write_token'], tuple(row))
