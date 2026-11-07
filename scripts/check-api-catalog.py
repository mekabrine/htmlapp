#!/usr/bin/env python3
"""Validate the catalog; optional bounded, read-only endpoint smoke checks.
HTTP/CORS success is not proof of provider terms or WKWebView compatibility.
"""
import argparse, concurrent.futures, datetime, ipaddress, json, re, time
import urllib.error, urllib.request
from pathlib import Path
from urllib.parse import urlsplit
ORIGIN = 'https://htmlapp.example'

def validate(data):
    errors, seen = [], set()
    if not isinstance(data, dict) or not isinstance(data.get('apis'), list):
        return ['Expected an object with an apis array']
    for e in data['apis']:
        if not isinstance(e, dict):
            errors.append('Entry must be an object'); continue
        ident = e.get('id', '?')
        for key in ('id','name','category','example','docs','auth','cors','method','use'):
            if not isinstance(e.get(key), str) or not e[key].strip(): errors.append(f'{ident}: missing/invalid {key}')
        if ident in seen: errors.append(f'duplicate id: {ident}')
        seen.add(ident)
        for key in ('example', 'docs'):
            u = urlsplit(str(e.get(key, '')))
            if u.scheme not in (('https','wss') if key == 'example' else ('https',)) or not u.hostname or u.username or u.password:
                errors.append(f'{ident}: invalid {key} URL')
            if u.hostname in ('localhost',) or (u.hostname or '').endswith(('.local', '.internal')):
                errors.append(f'{ident}: non-public host')
            try:
                if not ipaddress.ip_address(u.hostname or '').is_global: errors.append(f'{ident}: non-public IP')
            except ValueError: pass
        if re.search(r'[?&](?:key|api_key|apikey|token)=(?!YOUR_|DEMO_KEY)[^&{}]+', e.get('example',''), re.I):
            errors.append(f'{ident}: possible embedded credential')
    if data.get('meta', {}).get('count') != len(data['apis']): errors.append('meta.count mismatch')
    return errors

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl): return None

def check(e, timeout):
    url = e['example']
    if e['auth'] != 'none' or e['method'] != 'GET' or not url.startswith('https://') or re.search(r'[{}]|MBID|YOUR_', url):
        return e['id'], {'result':'skipped', 'reason':'keyed, streaming, mutation or placeholder example'}
    status, cors, note, mime = None, None, '', ''
    try:
        req = urllib.request.Request(url, headers={'User-Agent':'HTMLAppCatalogCheck/2.0 (+https://github.com/mekabrine/htmlapp)', 'Origin':ORIGIN, 'Accept':'application/json,*/*'})
        with urllib.request.build_opener(NoRedirect).open(req, timeout=timeout) as response:
            status=response.status; cors=response.headers.get('Access-Control-Allow-Origin'); mime=response.headers.get('Content-Type','')
            body=response.read(2_000_001)
            if len(body)>2_000_000: note='response-too-large'
            elif 'json' in mime:
                try: json.loads(body)
                except (ValueError, UnicodeError): note='invalid-json'
    except urllib.error.HTTPError as error:
        status=error.code; cors=error.headers.get('Access-Control-Allow-Origin'); note='http-error'
    except Exception as error: note=type(error).__name__ + ': ' + str(error)[:180]
    http_ok=status is not None and 200<=status<300 and not note
    cors_ok=cors in ('*',ORIGIN)
    ok=http_ok and (e['cors'] not in ('yes','likely') or cors_ok)
    return e['id'], {'result':'pass' if ok else 'fail', 'checkedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(), 'httpOK':http_ok, 'corsOK':cors_ok, 'corsHeader':cors, 'status':status, 'note':note}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--file',default='HTMLApp/Resources/htmlapp-api-catalog.json')
    parser.add_argument('--offline',action='store_true');parser.add_argument('--write',action='store_true');parser.add_argument('--only',default='');parser.add_argument('--timeout',type=float,default=8)
    a=parser.parse_args();path=Path(a.file);data=json.loads(path.read_text());errors=validate(data)
    if errors: print('\n'.join(errors));return 1
    print(f"Schema OK: {len(data['apis'])} entries",flush=True)
    if a.offline:return 0
    selected=set(filter(None,a.only.split(',')));groups={}
    for entry in data['apis']:
        if not selected or entry['id'] in selected: groups.setdefault(urlsplit(entry['example']).hostname,[]).append(entry)
    def host_checks(entries):
        results=[]
        for i, entry in enumerate(entries):
            if i:time.sleep(1.2)
            results.append(check(entry,max(1,min(30,a.timeout))))
        return results
    results={}
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for group in pool.map(host_checks,groups.values()):
            for ident,result in group:
                results[ident]=result;print(ident,json.dumps(result),flush=True)
    if a.write:
        for entry in data['apis']:
            if entry['id'] in results:entry['verified']=results[entry['id']];entry['verificationStatus']=results[entry['id']]['result']
        temporary=path.with_suffix('.tmp');temporary.write_text(json.dumps(data,indent=2)+'\n');temporary.replace(path)
    return int(any(result['result']=='fail' for result in results.values()))
if __name__=='__main__':raise SystemExit(main())
