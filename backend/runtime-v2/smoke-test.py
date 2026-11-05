#!/usr/bin/env python3
"""Real VPS acceptance checks. Uses one temporary deployment and deletes it."""
import argparse
import hashlib
import http.client
import json
import os
import secrets
import socket
import sqlite3
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

parser = argparse.ArgumentParser()
parser.add_argument('--local', action='store_true', help='Use the private manager socket before enabling v2 publicly.')
args = parser.parse_args()
if os.geteuid() != 0:
    parser.error('Run as root on the VPS.')
base = Path(__file__).resolve().parent
state = Path('/var/lib/htmlapp-runtime/runtime.sqlite3')


class Local(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(15)
        self.sock.connect('/run/htmlapp-runtime/control.sock')


def call(method, path, token='', body=None, session='', idem=None):
    connection = Local('localhost') if args.local else http.client.HTTPSConnection('htmlapp.hostish.site', timeout=20)
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if session:
        headers['X-HTMLApp-Session'] = session
    if idem:
        headers['Idempotency-Key'] = idem
    try:
        connection.request(method, path, body=json.dumps(body).encode() if body is not None else None, headers=headers)
        response = connection.getresponse()
        return response.status, json.loads(response.read())
    finally:
        connection.close()


def operation(method, path, token, body=None, expected_failure=False):
    status, pending = call(method, path, token, body, idem=secrets.token_hex(16))
    assert status == 202, (status, pending.get('error'))
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        status, result = call('GET', pending['statusURL'], token)
        assert status == 200, status
        if result['state'] == 'succeeded':
            assert not expected_failure, 'Invalid deployment unexpectedly succeeded'
            return result['result']
        if result['state'] == 'failed':
            assert expected_failure, result['result'].get('error')
            return result['result']
        time.sleep(0.5)
    raise AssertionError('Deployment operation timed out')


for attempt in range(60):
    try:
        status, capabilities = call('GET', '/v2/capabilities')
        if status == 200 and capabilities.get('sdkVersion') == 2:
            break
    except (OSError, ValueError, http.client.HTTPException):
        pass
    time.sleep(1)
else:
    raise SystemExit('Manager did not become ready. Inspect journalctl -u htmlapp-runtime.service.')

# Reclaim only abandoned, never-activated acceptance-test deployments.
# Earlier failed startup tests could not return their management credentials.
from manager import Manager
with open('/etc/htmlapp-template-gateway.env') as config:
    owner = next(line.split('=', 1)[1].strip().strip("\"'") for line in config if line.startswith('HTMLAPP_OWNER_KEY='))
local_manager = Manager(owner=owner)
with sqlite3.connect(state) as db:
    abandoned = db.execute("""SELECT a.id FROM apps a JOIN enrollments e ON e.hash=a.tenant
        WHERE e.label='Temporary acceptance test' AND e.active=0
        AND a.name='HTMLApp acceptance test' AND a.revision=0 AND a.deleted=0""").fetchall()
for (app_id,) in abandoned:
    operation('DELETE', '/v2/manage/apps/' + app_id, local_manager.keys(app_id)['managementKey'])

# Give the test its own temporary enrollment to avoid consuming a user's quota.
secret = secrets.token_hex(32)
fingerprint = hashlib.sha256(secret.encode()).hexdigest()
with sqlite3.connect(state) as db:
    db.execute('INSERT INTO enrollments VALUES(?,?,1,1)', (fingerprint, 'Temporary acceptance test'))

source = (base / 'examples/server.py').read_text()
manifest = json.loads((base / 'examples/manifest.json').read_text())
source += '''

@app.route('GET', '/isolation', access='app')
def isolation(request):
    import os, socket
    from urllib.parse import urlsplit
    gateway = urlsplit(os.environ['HTMLAPP_BROKER_URL']).hostname
    blocked = []
    for host, port in [(gateway, 22), ('1.1.1.1', 443)]:
        try:
            connection = socket.create_connection((host, port), timeout=1)
            connection.close()
            blocked.append(False)
        except OSError:
            blocked.append(True)
    return {'hostSecretsHidden': not os.path.exists('/etc/htmlapp-template-gateway.env'),
            'dockerSocketHidden': not os.path.exists('/var/run/docker.sock'),
            'networkBlocked': all(blocked), 'uid': os.getuid()}

@app.route('GET', '/quota-check', access='app')
def quota_check(request):
    import os
    written, stopped = 0, False
    try:
        with open('/data/quota-probe', 'wb', buffering=0) as output:
            for attempt in range(800):
                written += output.write(b'x' * 4096)
    except OSError as error:
        stopped = error.errno in (28, 122)
    finally:
        try:
            os.unlink('/data/quota-probe')
        except FileNotFoundError:
            pass
    return {'limited': stopped, 'written': written}
'''
manifest['routes'] += [{'method': 'GET', 'path': path, 'access': 'app'} for path in ('/isolation', '/quota-check')]
link = None
try:
    status, _ = call('POST', '/v2/deployments', 'invalid', {'source': source, 'manifest': manifest}, idem=secrets.token_hex(16))
    assert status == 403, 'Enrollment authorization was bypassed'
    request = {'clientID': secrets.token_hex(16), 'name': 'HTMLApp acceptance test', 'source': source, 'manifest': manifest}
    link = operation('POST', '/v2/deployments', secret, request)
    again = operation('POST', '/v2/deployments', secret, request)
    assert again['appID'] == link['appID'], 'Retry created a duplicate backend'
    runtime = '/v2/apps/' + link['appID']
    management = '/v2/manage/apps/' + link['appID']
    key, admin = link['publicKey'], link['managementKey']
    assert len(admin) == 20
    assert call('GET', management, key)[0] == 403
    assert call('GET', runtime + '/api/_platform/health', key)[0] in (400, 404)
    assert call('GET', runtime + '/api/items', key)[0] == 401
    status, identity = call('POST', runtime + '/api/resources', key, {'code': '2749'})
    assert status == 200, identity
    status, friend = call('POST', runtime + '/api/join', key, {'resource': identity['resource'], 'code': '2749'})
    assert status == 200
    item = {'requestID': secrets.token_hex(16), 'data': {'ciphertext': 'opaque-client-produced-ciphertext'}}
    status, receipt = call('POST', runtime + '/api/items', key, item, identity['session'])
    assert status == 200
    assert call('POST', runtime + '/api/items', key, item, identity['session'])[1] == receipt
    status, events = call('GET', runtime + '/api/items', key, session=friend['session'])
    assert status == 200 and len(events['events']) == 1
    status, isolated = call('GET', runtime + '/api/isolation', key)
    assert status == 200 and isolated['hostSecretsHidden'] and isolated['dockerSocketHidden'] and isolated['networkBlocked']
    assert isolated['uid'] != 0
    status, quota = call('GET', runtime + '/api/quota-check', key)
    assert status == 200 and quota['limited'] and quota['written'] < 2000000, 'Hard quota test failed'
    operation('POST', management + '/deploy', admin,
              {'baseRevision': 1, 'source': 'raise RuntimeError("intentional startup failure")', 'manifest': manifest}, expected_failure=True)
    assert call('GET', management, admin)[1]['revision'] == 1, 'Failed deployment changed the active revision'
    assert len(call('GET', runtime + '/api/items', key, session=friend['session'])[1]['events']) == 1
    updated = operation('POST', management + '/deploy', admin,
                        {'baseRevision': 1, 'source': source + '\n# second revision\n', 'manifest': manifest})
    assert updated['revision'] == 2
    restored = operation('POST', management + '/rollback', admin, {'baseRevision': 2})
    assert restored['revision'] == 3
    assert len(call('GET', runtime + '/api/items', key, session=friend['session'])[1]['events']) == 1
    if args.local:
        subprocess.run(['systemctl', 'restart', 'htmlapp-runtime.service'], check=True)
        for attempt in range(60):
            try:
                status, events = call('GET', runtime + '/api/items', key, session=friend['session'])
                if status == 200 and len(events['events']) == 1:
                    break
            except (OSError, ValueError, http.client.HTTPException):
                pass
            time.sleep(1)
        else:
            raise AssertionError('Manager restart did not restore the backend and its sessions')
    operation('DELETE', management, admin)
    operation('DELETE', management, admin)
    link = None
    print('PASS: real gVisor deployment, scopes, shared sessions, persistent events, retries, quota, network restrictions, failed update recovery, rollback and deletion.')
    print('APNs delivery was not tested. It requires a signed phone build and a real registered device.')
finally:
    if link is None and 'request' in locals():
        with sqlite3.connect(state) as db:
            pending = db.execute('SELECT id FROM apps WHERE tenant=? AND client=? AND deleted=0',
                                 (fingerprint, request['clientID'])).fetchone()
        if pending:
            link = {'appID': pending[0], 'managementKey': local_manager.keys(pending[0])['managementKey']}
    if link:
        try:
            operation('DELETE', '/v2/manage/apps/' + link['appID'], link['managementKey'])
        except Exception:
            print('Temporary deployment cleanup needs administrator attention. Backend ID: ' + link['appID'], file=sys.stderr)
    with sqlite3.connect(state) as db:
        db.execute('UPDATE enrollments SET active=0 WHERE hash=?', (fingerprint,))
