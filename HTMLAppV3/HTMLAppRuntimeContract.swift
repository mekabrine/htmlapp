import Foundation
enum HTMLAppRuntimeContract {
static let instructions = #"""
# HTMLApp Runtime v2 contract for Forge and client implementers

Read GET https://htmlapp.hostish.site/v2/capabilities and this document via
GET /v2/docs before planning a backend. These are real capabilities only when
apiVersion=2 is reachable. The current HTMLApp v1 native bridge cannot use v2.

## Generation output

Generate one complete UTF-8 server.py and a manifest JSON object, plus the HTML
frontend. Return these as separate artifacts. No keys belong in generated
source, frontend HTML, model messages, logs, URLs, or shareable Python files.
The native host owns enrollment and deployment. Generated HTML never invokes
management endpoints. Preserve a stable local clientID across creation retries.

Runtime: Python 3.12 standard library, cryptography 50.0.2, htmlapp_sdk v2.
Only a prebuilt image is executable. Requirements files, shell commands,
Dockerfiles, package installation, custom mounts and runtime flags are never
accepted from Forge. Import htmlapp_sdk, create app=App(), then register routes.
Use the SDK HTTPS broker for outbound APIs. Direct external sockets are blocked.

Example server:

```python
from htmlapp_sdk import App, Error
app = App()

@app.route('GET', '/health', access='public')
def health(request):
    return {'ok': True}

@app.route('POST', '/resources', access='app')
def create(request):
    return app.auth.create(request.json['code'])

@app.route('GET', '/items', access='session')
def items(request):
    return {'events': app.store.events(request.identity['resource'],
                                       request.query.get('after', ['0'])[0])}
```

Example manifest (must list EVERY route exactly, including access):

```json
{
  "sdkVersion": 2,
  "schemaVersion": 1,
  "routes": [
    {"method":"GET","path":"/health","access":"public"},
    {"method":"POST","path":"/resources","access":"app"},
    {"method":"GET","path":"/items","access":"session"}
  ],
  "checks": [
    {"path":"/health","expect":200},
    {"path":"/items","expect":401}
  ],
  "migrations": [],
  "outboundDomains": []
}
```

Routes support GET, POST, PUT, PATCH, DELETE and safe segments, including
/items/{id}. Handler request.params contains dynamic segments. Return a JSON
value. Raise Error(http_status, safe_message) for expected failures.
request.json is the parsed JSON body, request.query maps query keys to lists,
request.session is the X-HTMLApp-Session header. For a session route,
request.identity contains resource, subject, expires. Always use this identity
to scope data; do not trust a client-provided resource or subject instead.
Inputs are JSON objects. Binary/ciphertext uses base64 in JSON. Validate fields
and lengths in handlers. Schema describes routes; the source defines payloads.
Supply the frontend with that exact payload/response contract when generating.

Access public means deliberately anonymous. Access app requires the deployment's
publishable publicKey. That key is shared with app users and does NOT protect
private data from another user. Access session requires both the app key and a
current resource-scoped session. Choose session for sensitive routes by default.
The SDK's app.route defaults to session. Checks are GET-only and run against the
candidate, with no session. They are readiness checks, not proof of correctness
of all generated app logic. A public route must be intentional and safe.

## Deployment and management (native host only)

GET /v2/enrollment with the enrollment secret verifies pairing and returns
paired, maxApps and activeApps. It never returns app IDs or management keys.
New per-person v2 secrets are verified here, not through v1's pairing endpoint.

Every request body is JSON with Content-Type: application/json.
Send Authorization: Bearer <credential>. Never put credentials in URLs.

POST /v2/deployments, authenticated by an enrollment secret:
{"clientID":"stable-local-uuid","name":"My app","source":"...","manifest":{...}}

POST /v2/manage/apps/{appID}/deploy, authenticated by managementKey:
{"baseRevision":1,"source":"...","manifest":{...}}

POST /v2/manage/apps/{appID}/rollback with {"baseRevision":2} deploys the previous
source against current data. It rejects a schema-version change. It creates a
new revision, never discards current data. Use a forward repair for schema issues.

POST /v2/manage/apps/{appID}/restart with {"baseRevision":3} restarts current code.
DELETE /v2/manage/apps/{appID} deletes the backend. Repeated deletion is safe.
All mutations require Idempotency-Key: <random stable operation UUID>.
Use a new operation key for a changed request. Keep it for retries of the same
request. A deleted creation clientID is tombstoned and cannot recreate its app.

These mutations return HTTP 202 with:
{"operationID":"...","state":"queued","statusURL":"/v2/operations/..."}
Poll that path using the SAME credential. States queued/running are pending.
On succeeded, result contains backend details (and keys for creation only).
On failed, result.error and result.status describe a safe diagnostic. Fix the
source/manifest and issue a new operation, respecting current revision.
After a manager restart, interrupted operations fail explicitly. Refresh app
status before retrying. Creation uses the same clientID and returns the same
backend. Existing deployment keys are never reissued by app status/schema APIs.
Deployment IDs and results are retained for 24 hours. Keep keys in Keychain.

GET /v2/manage/apps/{appID} returns state, revision, URLs and limits.
GET /v2/manage/apps/{appID}/source returns current server.py and manifest.
GET /v2/manage/apps/{appID}/logs returns safe status information only. Arbitrary
application output remains VPS-administrator-only to avoid leaking user data
or secrets. Startup diagnostics include safe exception categories/line numbers.

Creation returns appID (12 characters), managementKey (20 characters), publicKey,
apiBaseURL, schemaURL, revision, state, workspaceLimitBytes, pushConfigured.
The native host must keep managementKey and Python source local and exclude
both from ordinary app sharing. The backend service cannot enforce iOS export
rules; the future client implementation must enforce them.

## Runtime URL and authorization contract

Actual base URL:
https://htmlapp.hostish.site/v2/apps/{appID}/api

A generated /items handler is reached at:
https://htmlapp.hostish.site/v2/apps/{appID}/api/items

The host injects this base URL. The frontend uses relative route paths through
a future native backend.request API. It must not guess ports or sandbox IPs.
External tools can call the same HTTPS URLs with their appropriate credentials.
Use Authorization: Bearer <publicKey> for app/session routes, and
X-HTMLApp-Session: <session> for session routes.

GET /v2/apps/{appID}/schema returns the current manifest with publicKey auth.
The publicKey is publishable app access, not authorization to private messages.
Public routes can be called anonymously. Never embed an enrollment or management
secret in HTML/JavaScript, external website code, shared links or QR codes.

No WebSocket/SSE transport is promised by v2. Use cursor polling for events
while foregrounded, stop on suspension, and resume from the last cursor.
Catch offline/unavailable errors and retry with backoff. Writes need request IDs
and transactional deduplication to avoid duplicates after lost responses.
Use incremental polling, not full unbounded history. The included example shows
atomic event+receipt insertion and resource-scoped cursor reads.

## SDK reference

app.store.get(key, default=None), put(key, JSON), delete(key).
app.store.transaction() yields a sqlite3 connection using BEGIN IMMEDIATE.
Use that transaction for multi-step consistency, deduplication and events.
Exceptions roll back. SQLite is at /data/app.sqlite3; custom tables are allowed.
app.store.publish(resource, JSON) returns an increasing event ID.
app.store.events(resource, after=0, limit=100) returns [{id,data},...].
Use transactions to coordinate event publication with other writes.

app.auth.create(code) -> {resource, session, subject, expiresAt}.
app.auth.join(resource, code) -> {session, subject, expiresAt}.
Resource IDs are random and must be included in invitations.
Codes have 4..128 characters and are stored as salted scrypt verifiers.
Five failed attempts per resource per five-minute window are allowed. Successful
joins reset the counter. Attempts persist across process restart. Resource-wide
limits can temporarily block legitimate users during an attack.
Sessions are random 256-bit tokens, stored hashed, expire after 24 hours, and
are checked against resource membership on every authenticated route.
app.auth.require(token, resource=None) -> {resource,subject,expires}.
app.auth.is_member(resource,subject) -> bool.
app.auth.revoke(resource,subject) revokes that membership and all its sessions.
Only call revoke from a properly authorized owner/admin route implemented by
the application. SDK membership itself has no implicit resource-owner role.
A resource PIN gives shared participant access. Build separate owner authority
where the prompt requires moderation. Do not let any participant revoke others.

@app.every(seconds) registers an interval task. Allowed interval 30..86400.
Schedules restart with the worker, do not catch up missed runs, and must be
idempotent. Persist a last-run marker for jobs that need recovery. Failures are
retried at the next interval; exact-once scheduling is not guaranteed.

app.fetch(domain, path, method='GET', json=None, headers=None) -> {status,data}.
Declare exact lowercase outboundDomains (up to 8) in the manifest. HTTPS only,
port 443, public IPv4 resolution only, no redirects, 16 KiB body / 64 KiB response.
Headers allowed: Accept, Content-Type, Authorization. Use escaped query strings;
path segments may not contain percent escapes, traversal or backslashes.
The broker validates DNS answers and pins the connection to the validated IP.
External effects are disabled until candidate validation has completed.
External services may require user-supplied credentials and their own quotas.

app.notify(resource,title='New activity',body='Open the app to view it.') -> {queued}.
A queued notification is not an APNs delivery confirmation. The durable broker
checks current membership/subscription before delivery, retries transient errors
up to three times, and expires jobs after an hour. Crashes can produce duplicate
pushes; clients can deduplicate htmlapp_notification_id. Invalid APNs device
tokens are removed. App events remain the source of truth for new information.

Device subscriptions use PUT /v2/apps/{appID}/devices with publicKey auth:
{"session":"current-resource-session","deviceToken":"APNs-hex-token"}.
DELETE the same endpoint/body to unsubscribe. Membership revocation blocks
future delivery. Register each authorized resource and device separately.
Maximum 100 subscriptions per app. 6 notification batches/resource/minute,
30 batches/app/minute, maximum 100 pending deliveries/app. APNs credentials stay
on the VPS. iOS signing/entitlements, correct APNs environment, and user consent
are mandatory. A device token is not a secret that authorizes reading messages.

## Encryption and sharing requirements for future clients

This SDK provides authorization and ciphertext transport/storage. It does not
implement a group encryption protocol or encrypted invitations. Four-digit PINs
have only 10000 possibilities and cannot be the sole strong encryption key.
For E2EE, clients must encrypt/decrypt with strong device-held keys and a
reviewed invitation/key-rotation protocol. Store only ciphertext on the backend.
Send generic notifications without plaintext message contents. Do not claim
E2EE from HTTPS, PIN verification, server-side encryption or this example alone.

Shared users join the same appID/service with the publishable publicKey and an
invitation. The resource ID identifies the chat/list/etc; the PIN authorizes
joining its session. A future encrypted invitation also carries protected key
material. A friend deleting their local copy unsubscribes that device and must
not DELETE the creator's deployment. Only the owner holds managementKey.
Forking an independent backend is a distinct action with its own appID/data.

## Lifecycle and limits

Six active deployments globally, three per enrollment secret by default.
Use separate secrets for trusted people; the VPS admin can issue/revoke them.
A shared secret is not device attestation and a Discord post can consume capacity.
Capacity is conservative for the current one-CPU, approximately 4 GiB VPS.
Each deployment uses a gVisor sandbox, 256 MiB memory, 0.35 CPU, 96 processes,
read-only root/code, no privileges, no host mounts or Docker socket, a private
internal network and a narrowly scoped broker. Direct host/Internet sockets are
blocked. Repeated crashes stop after five automatic Docker retries and surface
as failed; authenticated restart can retry after the cause is fixed.

An XFS project quota of 1952 KiB (1998848 bytes, below 2 MB) and 256 inodes covers
all app code, current data, temporary files, previous source and staged data.
Full storage returns errors; no user messages are silently purged. During an
update, both old data and a candidate copy must fit, so an app close to its limit
can be unable to update until space is freed. The root image/SDK are shared
infrastructure. Runtime metadata, capped Docker logs, and bounded push jobs live
outside the per-app workspace and have separate platform limits.

Updates stop the old worker, copy data without following symlinks/hardlinks,
apply migrations transactionally in the candidate sandbox, verify declared
routes/checks, then switch the active revision. Requests during the update
return 503. External effects are blocked during validation. Failed validation
restores the old source/data. Retain backward-compatible routes for existing
shared clients; this service does not atomically update HTML on other phones.

Migrations are a list of single SQLite statements run only when schemaVersion
increases (or initializes). Each release supplies the complete migration from
the immediately previous schema; do not repeat historical migrations in every
release. Transactions, ATTACH, DETACH, PRAGMA and multi-statement strings are
rejected inside migrations. Failed migrations leave the old data intact.
SQLite changes performed by arbitrary application code are that app's own
responsibility. Deployment rollback supports matching schema versions only.

Implement handlers and tests for the actual prompt using these generic APIs.
Never replace missing app logic with a static unsupported-feature screen or
invent successful network responses. Ask for genuinely unavailable external
credentials when needed. Keep setup errors actionable and preserve user data.

"""#
}
