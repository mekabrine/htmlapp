"""Run only the trusted bundled example locally. Never execute uploaded app code here."""
import http.client
import json
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest

BASE = Path(__file__).resolve().parents[1]


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.database = self.root / 'data.sqlite3'
        self.manifest = json.loads((BASE / 'examples/manifest.json').read_text())
        (self.root / 'server.py').write_text((BASE / 'examples/server.py').read_text())
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            self.port = sock.getsockname()[1]
        self.process = None

    def tearDown(self):
        self.stop()
        self.temp.cleanup()

    def stop(self):
        if self.process:
            self.process.terminate()
            self.process.wait(timeout=5)
            self.process = None

    def start(self):
        (self.root / 'manifest.json').write_text(json.dumps(self.manifest))
        env = {**os.environ, 'HTMLAPP_CODE_DIRECTORY': str(self.root), 'HTMLAPP_DATABASE': str(self.database),
               'HTMLAPP_PORT': str(self.port), 'HTMLAPP_BROKER_TOKEN': 'test-broker', 'PYTHONPATH': str(BASE)}
        self.process = subprocess.Popen([sys.executable, str(BASE / 'worker.py')], env=env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(100):
            if self.process.poll() is not None:
                return False
            try:
                if self.call('GET', '/health')[0] == 200:
                    return True
            except OSError:
                pass
            time.sleep(0.03)
        raise AssertionError('worker did not start')

    def call(self, method, path, body=None, session='', internal=False):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=3)
        try:
            headers = {'Content-Type': 'application/json', 'X-HTMLApp-Session': session}
            if internal:
                headers['Authorization'] = 'Bearer test-broker'
            connection.request(method, path, body=json.dumps(body) if body is not None else None, headers=headers)
            response = connection.getresponse()
            return response.status, json.loads(response.read())
        finally:
            connection.close()

    def test_real_http_sessions_shared_events_and_restart(self):
        self.assertTrue(self.start())
        status, creator = self.call('POST', '/resources', {'code': '1234'})
        self.assertEqual(status, 200)
        status, friend = self.call('POST', '/join', {'resource': creator['resource'], 'code': '1234'})
        self.assertEqual(status, 200)
        self.assertEqual(self.call('GET', '/items')[0], 401)
        self.assertEqual(self.call('GET', '/_platform/health')[0], 403)
        self.assertEqual(self.call('GET', '/_platform/health', internal=True)[0], 200)
        body = {'requestID': 'request0001', 'data': {'ciphertext': 'opaque'}}
        first = self.call('POST', '/items', body, creator['session'])
        self.assertEqual(first[0], 200)
        self.assertEqual(first, self.call('POST', '/items', body, creator['session']))
        self.stop()
        self.assertTrue(self.start())
        status, result = self.call('GET', '/items', session=friend['session'])
        self.assertEqual(status, 200)
        self.assertEqual(len(result['events']), 1)
        self.assertEqual(result['events'][0]['data'], {'ciphertext': 'opaque'})

    def test_migration_failure_rolls_back_schema_and_data(self):
        self.manifest['migrations'] = ['CREATE TABLE custom(value TEXT)', "INSERT INTO custom VALUES('keep')"]
        self.assertTrue(self.start())
        self.stop()
        self.manifest['schemaVersion'] = 2
        self.manifest['migrations'] = ['DELETE FROM custom', 'THIS IS INVALID SQL']
        self.assertFalse(self.start())
        self.stop()
        with sqlite3.connect(self.database) as db:
            self.assertEqual(db.execute('SELECT * FROM custom').fetchone()[0], 'keep')
            self.assertEqual(db.execute('SELECT version FROM _htmlapp_schema').fetchone()[0], 1)


if __name__ == '__main__':
    unittest.main()
