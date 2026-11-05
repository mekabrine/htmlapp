import os
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from htmlapp_sdk import App, Auth, Error, Request, Store


class SDKTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.app = App(str(Path(self.temp.name) / 'test.sqlite3'))

    def tearDown(self):
        self.temp.cleanup()

    def test_session_resource_scope_and_revocation(self):
        first = self.app.auth.create('1234')
        second = self.app.auth.create('5678')
        with self.assertRaises(Error):
            self.app.auth.require(first['session'], second['resource'])
        self.assertEqual(self.app.auth.require(first['session'])['resource'], first['resource'])
        self.app.auth.revoke(first['resource'], first['subject'])
        with self.assertRaises(Error):
            self.app.auth.require(first['session'])
        self.assertFalse(self.app.auth.is_member(first['resource'], first['subject']))

    def test_guesses_persist_between_auth_instances(self):
        resource = self.app.auth.create('1234')['resource']
        for _ in range(5):
            with self.assertRaises(Error) as error:
                self.app.auth.join(resource, '9999')
            self.assertEqual(error.exception.status, 403)
        with self.assertRaises(Error) as error:
            Auth(self.app.store).join(resource, '1234')
        self.assertEqual(error.exception.status, 429)

    def test_route_scope_and_parameters(self):
        @self.app.route('GET', '/items/{id}')
        def read(request):
            return {'id': request.params['id'], 'subject': request.identity['subject']}
        session = self.app.auth.create('1234')
        with self.assertRaises(Error):
            self.app.handle(Request('GET', '/items/abc', {}, {}, {}))
        response = self.app.handle(Request('GET', '/items/abc', {'X-HTMLApp-Session': session['session']}, {}, {}))
        self.assertEqual(response['id'], 'abc')
        self.assertEqual(response['subject'], session['subject'])

    def test_store_rollback_and_event_cursor(self):
        self.app.store.put('x', {'value': 1})
        with self.assertRaises(RuntimeError):
            with self.app.store.transaction() as db:
                db.execute("UPDATE kv SET value='2' WHERE key='x'")
                raise RuntimeError('abort')
        self.assertEqual(self.app.store.get('x'), {'value': 1})
        one = self.app.store.publish('a', {'text': 'one'})
        self.app.store.publish('b', {'text': 'private'})
        two = self.app.store.publish('a', {'text': 'two'})
        self.assertEqual(self.app.store.events('a', one), [{'id': two, 'data': {'text': 'two'}}])
        self.assertEqual(Store(self.app.store.path).events('a', one)[0]['id'], two)


if __name__ == '__main__':
    unittest.main()
