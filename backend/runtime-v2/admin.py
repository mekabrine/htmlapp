#!/usr/bin/env python3
"""Local root-only enrollment administration. Never exposes the VPS owner key."""
import argparse
import hashlib
import os
import secrets
import sqlite3

parser = argparse.ArgumentParser()
commands = parser.add_subparsers(dest='action', required=True)
create = commands.add_parser('issue-secret')
create.add_argument('--label', required=True)
create.add_argument('--max-apps', type=int, default=3)
commands.add_parser('list-secrets')
revoke = commands.add_parser('revoke-secret')
revoke.add_argument('--fingerprint', required=True)
rotate = commands.add_parser('rotate-app-keys')
rotate.add_argument('--app-id', required=True)
args = parser.parse_args()
if os.geteuid() != 0:
    parser.error('Run as root on the VPS.')
with sqlite3.connect('/var/lib/htmlapp-runtime/runtime.sqlite3') as db:
    if args.action == 'issue-secret':
        if not 1 <= args.max_apps <= 6 or not 1 <= len(args.label) <= 80:
            parser.error('Use max-apps 1..6 and a short label.')
        token = secrets.token_hex(32)
        fingerprint = hashlib.sha256(token.encode()).hexdigest()
        db.execute('INSERT INTO enrollments VALUES(?,?,1,?)', (fingerprint, args.label, args.max_apps))
        print('Save this secret privately. It is shown once:')
        print(token)
    elif args.action == 'list-secrets':
        for row in db.execute('SELECT hash,label,active,max_apps FROM enrollments'):
            print(*row)
    elif args.action == 'rotate-app-keys':
        import hmac, base64, json, re
        if not re.fullmatch(r'[A-Z2-7]{12}', args.app_id):
            parser.error('Invalid backend ID.')
        cursor = db.execute('UPDATE apps SET key_generation=key_generation+1 WHERE id=? AND deleted=0', (args.app_id,))
        if not cursor.rowcount:
            parser.error('Backend not found.')
        generation = db.execute('SELECT key_generation FROM apps WHERE id=?', (args.app_id,)).fetchone()[0]
        with open('/etc/htmlapp-template-gateway.env') as config:
            owner = next(line.split('=', 1)[1].strip().strip('\"\'') for line in config if line.startswith('HTMLAPP_OWNER_KEY='))
        def derive(scope, length):
            raw = hmac.digest(owner.encode(), ('htmlapp.v2:' + args.app_id + ':' + str(generation) + ':' + scope).encode(), 'sha256')[:length]
            return base64.urlsafe_b64encode(raw).rstrip(b'=').decode()
        print(json.dumps({'appID': args.app_id, 'managementKey': derive('management',15), 'publicKey': derive('runtime',24)}))
    else:
        cursor = db.execute('UPDATE enrollments SET active=0 WHERE hash=?', (args.fingerprint,))
        print('Revoked.' if cursor.rowcount else 'Fingerprint not found.')
