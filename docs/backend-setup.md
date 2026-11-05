# Automatic Hostish backends in HTMLApp 1.7.2

Upgrade the gateway with the matching auto-link package, then paste its VPS
provisioning key once in **Settings → AI & Voice → Automatic backends**.
Forge apps that need an approved document or notification backend provision
and link on save. For existing apps, including imports and transferred copies,
opening **Developer → Backend** also creates and links the declared backend.
Importing alone does not create a backend. Retrying uses the same backend,
and transferred copies get separate credentials. Keep the owner key on the VPS.

The steps below are a fallback for existing backends or older builds.

HTMLApp 1.7.0 uses the existing template gateway at
`https://htmlapp.hostish.site`. Leave the Hostish agent in Screen. If the
gateway smoke test already passed, no reinstall or agent changes are needed.
The gateway starts at boot; restart the Screen agent after a VPS reboot.

## 1. Provision a backend on the VPS

Run this as root. Set the template to `document` or `notification`, and change
the display name. The owner key is read locally and sent only to loopback.
The result includes the new app's keys. Paste it into HTMLApp, not into chat.

```bash
python3 - <<'PY'
import json
from pathlib import Path
from urllib.request import Request, urlopen

template = "notification"
name = "Notify My Phone"
key = next(line.split("=", 1)[1] for line in
           Path("/etc/htmlapp-template-gateway.env").read_text().splitlines()
           if line.startswith("HTMLAPP_OWNER_KEY="))
request = Request(
    "http://127.0.0.1:45806/v1/apps",
    data=json.dumps({"template": template, "name": name}).encode(),
    headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
    method="POST",
)
with urlopen(request, timeout=10) as response:
    print(json.dumps(json.load(response), separators=(",", ":")))
PY
```

## 2. Link and test on the phone

1. Save an HTML app, enable Developer Mode, then long-press its Library icon.
2. Open **Developer → BACKEND → Backend details**. Paste the complete JSON and
   tap **Verify and link**. The panel displays the ID, template and revision.
3. For a document template, use **Edit JSON data** to save a sample. Turn on
   public-key reads only for a document that can be disclosed to anyone holding
   the read key. The app can then call `HTMLAppNative.backend.read()`.
4. For a notification template, set up APNs on the VPS as described in the
   gateway README. A signed build with the right APNs entitlement is required.
   Tap **Register this phone**, then **Send test notification**. The notification
   URL and send-only key can be copied from the panel.

Forge can generate a UI for these runtime operations when the prompt needs a
server. App registration remains a VPS owner action. There is no API to create
a backend, deploy code, copy a key, or delete a backend from generated HTML.

## 3. Understand source, sharing and deletion

- A locally attached Python file can be viewed and explicitly shared from the
  Backend panel. It is a local reference. Approved templates do not deploy a
  Python file per app, and attaching a file does not run or deploy it.
- Nearby Transfer creates a detached copy. The device-only link, private
  keys and local source are not part of the transfer. Keep credentials out of
  app HTML and out of any Python file you explicitly share.
- Deleting a linked app requests deletion of the remote backend and its data.
  While offline, the native host retains the key and retries when it next runs
  online. Use **Unlink from this app** first if you want to keep the server.
