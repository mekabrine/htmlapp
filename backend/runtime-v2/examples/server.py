"""Generic shared resources. Payloads may contain ciphertext from a future E2EE client."""
from htmlapp_sdk import App, Error
app = App()


@app.route('GET', '/health', access='public')
def health(request):
    return {'ok': True}


@app.route('POST', '/resources', access='app')
def create(request):
    return app.auth.create(request.json['code'])


@app.route('POST', '/join', access='app')
def join(request):
    return app.auth.join(request.json['resource'], request.json['code'])


@app.route('GET', '/items', access='session')
def read(request):
    return {'events': app.store.events(request.identity['resource'], request.query.get('after', ['0'])[0])}


@app.route('POST', '/items', access='session')
def write(request):
    resource = request.identity['resource']
    value = request.json['data']
    key = request.json['requestID']
    if not isinstance(key, str) or not 8 <= len(key) <= 80:
        raise Error(400, 'Use a stable requestID for safe retries.')
    # Idempotency and the event must be committed in the same transaction.
    import json
    from htmlapp_sdk import encode
    with app.store.transaction() as db:
        receipt = resource + ':' + request.identity['subject'] + ':' + key
        old = db.execute('SELECT value FROM kv WHERE key=?', (receipt,)).fetchone()
        if old:
            return json.loads(old[0])
        payload = encode(value)
        if len(payload) > 4096:
            raise Error(413, 'Use payloads under 4096 bytes.')
        cursor = db.execute('INSERT INTO events(resource,payload) VALUES(?,?)', (resource, payload))
        result = {'id': cursor.lastrowid}
        db.execute('INSERT INTO kv VALUES(?,?)', (receipt, encode(result)))
    return result


@app.route('POST', '/notify', access='session')
def notify(request):
    # Keep plaintext content out of pushes for encrypted applications.
    return app.notify(request.identity['resource'], 'New activity', 'Open the app to view it.')
