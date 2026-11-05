import copy
import io
import json
import os
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from manager import Failure, Manager, copy_data, safe_path, validate_bundle, command, Engine
from api import API

SOURCE = 'from htmlapp_sdk import App\napp=App()\n'
MANIFEST = {'sdkVersion': 2, 'schemaVersion': 1,
            'routes': [{'method': 'GET', 'path': '/health', 'access': 'public'}],
            'checks': [{'path': '/health', 'expect': 200}]}


class FakeEngine:
    def __init__(self, root):
        self.root = root
        self.fail_check = False
        self.fail_destroy = False
        self.running = set()

    def stage(self, row, revision, source, manifest):
        target = self.root / row['id'] / revision
        target.mkdir(parents=True)
        (target / 'server.py').write_text(source)
        (target / 'manifest.json').write_text(json.dumps(manifest))
        (target / 'data').mkdir()
        old = self.root / row['id'] / str(row['current']) / 'data' / 'value'
        if old.exists():
            (target / 'data' / 'value').write_text(old.read_text())

    def start(self, row, revision):
        self.running.add(revision)

    def stop(self, row):
        self.running.discard(row['current'])

    def check(self, *_):
        if self.fail_check:
            raise Failure(422, 'startup failed')

    def remove(self, row, revision):
        import shutil
        self.running.discard(revision)
        shutil.rmtree(self.root / row['id'] / revision, ignore_errors=True)

    def cleanup(self, row):
        pass

    def destroy(self, row):
        if self.fail_destroy:
            raise Failure(503, 'docker unavailable')
        self.running.clear()

    def request(self, row, revision, method, path, body=None, **kwargs):
        return 200, {'path': path}


class ManagerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name) / 'apps'
        self.engine = FakeEngine(root)
        self.manager = Manager(engine=self.engine, root=root, state=Path(self.temp.name) / 'state',
                               owner='a' * 64, provision='b' * 64)

    def tearDown(self):
        self.temp.cleanup()

    def create(self, client='client0001'):
        return self.manager.create('b' * 64, {'clientID': client, 'name': 'Test', 'source': SOURCE, 'manifest': copy.deepcopy(MANIFEST)})

    def test_create_retry_and_key_scopes(self):
        first = self.create()
        self.assertEqual(first['appID'], self.create()['appID'])
        self.assertEqual(first['managementKey'], self.create()['managementKey'])
        self.assertEqual(len(first['managementKey']), 20)
        with self.assertRaises(Failure):
            self.manager.require_manager(first['appID'], first['publicKey'])
        other = self.create('client0002')
        with self.assertRaises(Failure):
            self.manager.require_manager(first['appID'], other['managementKey'])

    def test_failed_candidate_restores_old_revision_and_data(self):
        first = self.create()
        row = self.manager.row(first['appID'])
        (self.manager.directory(row) / 'data' / 'value').write_text('keep me')
        self.engine.fail_check = True
        with self.assertRaises(Failure):
            self.manager.deploy(first['appID'], first['managementKey'], {'baseRevision': 1, 'source': SOURCE + '# edit', 'manifest': MANIFEST})
        current = self.manager.row(first['appID'])
        self.assertEqual(current['revision'], 1)
        self.assertEqual(current['current'], row['current'])
        self.assertIn(current['current'], self.engine.running)
        self.assertEqual((self.manager.directory(current) / 'data' / 'value').read_text(), 'keep me')

    def test_conflicting_edits_and_data_preserving_rollback(self):
        first = self.create()
        row = self.manager.row(first['appID'])
        (self.manager.directory(row) / 'data' / 'value').write_text('new data')
        self.manager.deploy(first['appID'], first['managementKey'], {'baseRevision': 1, 'source': SOURCE + '# edit', 'manifest': MANIFEST})
        with self.assertRaises(Failure):
            self.manager.deploy(first['appID'], first['managementKey'], {'baseRevision': 1, 'source': SOURCE, 'manifest': MANIFEST})
        row = self.manager.row(first['appID'])
        (self.manager.directory(row) / 'data' / 'value').write_text('latest data')
        result = self.manager.rollback(first['appID'], first['managementKey'], {'baseRevision': 2})
        self.assertEqual(result['revision'], 3)
        self.assertEqual((self.manager.directory(self.manager.row(first['appID'])) / 'data' / 'value').read_text(), 'latest data')

    def test_deleted_ids_and_cleanup_retry(self):
        first = self.create()
        self.engine.fail_destroy = True
        with self.assertRaises(Failure):
            self.manager.delete(first['appID'], first['managementKey'])
        with self.assertRaises(Failure) as error:
            self.create()
        self.assertEqual(error.exception.status, 410)
        self.engine.fail_destroy = False
        self.assertTrue(self.manager.delete(first['appID'], first['managementKey'])['deleted'])

    def test_route_restrictions_and_public_access(self):
        first = self.create()
        self.assertEqual(self.manager.proxy(first['appID'], 'GET', '/health', '', '', None)[0], 200)
        for path in ('/_platform/health', '/%2e%2e/secret', '/../secret', '//health', '/a\\b'):
            with self.assertRaises(Failure):
                self.manager.proxy(first['appID'], 'GET', path, first['publicKey'], '', None)
        with self.assertRaises(Failure):
            self.manager.proxy(first['appID'], 'GET', '/undeclared', first['publicKey'], '', None)

    def test_copy_rejects_symlinks_and_hardlinks(self):
        root = Path(self.temp.name)
        data = root / 'untrusted'
        data.mkdir()
        (data / 'link').symlink_to('/etc/passwd')
        with self.assertRaises(OSError):
            copy_data(data, root / 'output')
        (data / 'link').unlink()
        (data / 'file').write_text('x')
        os.link(data / 'file', data / 'link')
        with self.assertRaises(Failure):
            copy_data(data, root / 'output2')

    def test_operation_idempotency_and_owner_binding(self):
        api = API(self.manager)
        body = {'clientID': 'client0001', 'name': 'Test', 'source': SOURCE, 'manifest': MANIFEST}
        first = api.operations.submit('b' * 64, 'operation0001', 'create', None, body)
        api.operations.work.join()
        again = api.operations.submit('b' * 64, 'operation0001', 'create', None, body)
        self.assertEqual(first['operationID'], again['operationID'])
        self.assertEqual(again['state'], 'succeeded')
        with self.assertRaises(Failure):
            api.operations.get('c' * 64, first['operationID'])
        with self.assertRaises(Failure):
            api.operations.submit('b' * 64, 'operation0001', 'create', None, {**body, 'name': 'Changed'})


    def test_unassigned_or_missing_ip_is_retryable_startup(self):
        first = self.create()
        row = self.manager.row(first['appID'])
        engine = Engine(self.manager)
        for networks in ({}, {engine.network(row): {'IPAddress': ''}}):
            with patch('manager.command', return_value=json.dumps(networks)):
                with self.assertRaises(Failure) as error:
                    engine.request(row, row['current'], 'GET', '/health')
                self.assertEqual(error.exception.status, 503)

    def test_code_remains_readable_with_private_service_umask(self):
        import stat
        first = self.create()
        row = self.manager.row(first['appID'])
        engine = Engine(self.manager)
        revision = 'a' * 24
        previous_umask = os.umask(0o077)
        try:
            with patch('manager.command'), patch('manager.os.chown'):
                engine.stage(row, revision, SOURCE, MANIFEST)
        finally:
            os.umask(previous_umask)
        target = self.manager.directory(row, revision)
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o755)
        self.assertEqual(stat.S_IMODE((target / 'server.py').stat().st_mode), 0o444)
        self.assertEqual(stat.S_IMODE((target / 'manifest.json').stat().st_mode), 0o444)

    def test_failed_inspect_output_is_not_an_existing_container(self):
        import subprocess
        result = subprocess.CompletedProcess(['docker'], 1, stdout='[]', stderr='not found secret=' + 'a' * 43)
        with patch('manager.subprocess.run', return_value=result):
            self.assertEqual(command('docker', 'inspect', 'missing', check=False), '')
            with self.assertRaises(Failure) as error:
                command('docker', 'inspect', 'missing')
            self.assertIn('not found', error.exception.message)
            self.assertNotIn('a' * 43, error.exception.message)
            self.assertIn('[redacted]', error.exception.message)

    def test_key_rotation_invalidates_old_management_and_app_keys(self):
        first = self.create()
        with self.manager.db() as db:
            db.execute('UPDATE apps SET key_generation=key_generation+1 WHERE id=?', (first['appID'],))
        with self.assertRaises(Failure):
            self.manager.require_manager(first['appID'], first['managementKey'])
        renewed = self.create()
        self.assertNotEqual(first['managementKey'], renewed['managementKey'])
        self.assertNotEqual(first['publicKey'], renewed['publicKey'])
        self.assertEqual(first['appID'], renewed['appID'])

    def test_revoked_enrollment_and_per_person_limits(self):
        self.create('client0001')
        self.create('client0002')
        self.create('client0003')
        with self.assertRaises(Failure) as error:
            self.create('client0004')
        self.assertEqual(error.exception.status, 409)
        with self.manager.db() as db:
            db.execute('UPDATE enrollments SET active=0')
        with self.assertRaises(Failure) as error:
            self.create('client0001')
        self.assertEqual(error.exception.status, 403)

    def test_outbound_allowlist_and_private_dns_are_rejected(self):
        first = self.create()
        with self.assertRaises(Failure):
            self.manager.fetch(first['appID'], {'domain': 'example.com', 'path': '/', 'method': 'GET'})
        row = self.manager.row(first['appID'])
        manifest = copy.deepcopy(MANIFEST)
        manifest['outboundDomains'] = ['example.com']
        (self.manager.directory(row) / 'manifest.json').write_text(json.dumps(manifest))
        with patch('manager.command', return_value='127.0.0.1 STREAM example.com'):
            with self.assertRaises(Failure) as error:
                self.manager.fetch(first['appID'], {'domain': 'example.com', 'path': '/data', 'method': 'GET'})
            self.assertEqual(error.exception.status, 403)
        self.assertTrue(safe_path('/items?query=hello%20world'))
        self.assertFalse(safe_path('/%2e%2e/secret'))

    def test_manifest_cannot_supply_runtime_flags_or_mounts(self):
        for field in ('dockerArgs', 'mounts', 'privileged', 'dependencies'):
            with self.assertRaises(Failure):
                validate_bundle({'source': SOURCE, 'manifest': {**MANIFEST, field: []}})

    def test_notification_jobs_and_unsubscribe_are_scoped(self):
        first = self.create()
        self.manager.push = lambda *_: None
        class SessionEngine(FakeEngine):
            def request(self, *args, **kwargs):
                return 200, {'resource': 'resource-a', 'subject': 'subject-a'}
        self.manager.engine = SessionEngine(self.engine.root)
        token = 'aa' * 32
        body = {'session': 'valid-test-session', 'deviceToken': token}
        self.manager.device(first['appID'], first['publicKey'], body)
        self.assertEqual(self.manager.notify(first['appID'], {'resource': 'resource-a', 'title': 'New', 'body': 'Open app'})['queued'], 1)
        self.manager.device(first['appID'], first['publicKey'], body, delete=True)
        with self.manager.db() as db:
            self.assertEqual(db.execute('SELECT count(*) FROM push_jobs').fetchone()[0], 0)
            self.assertEqual(db.execute('SELECT count(*) FROM devices').fetchone()[0], 0)


if __name__ == '__main__':
    unittest.main()
