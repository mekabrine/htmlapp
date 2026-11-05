# HTMLApp 1.8.0 runtime integration

The server runtime passed local and public acceptance on the owner's VPS.
The client now carries inert source/manifest JSON in a typed application/json
script with id htmlapp-backend-v2. Saving validates and deploys it before the
frontend is saved; rejected candidates can trigger two bounded Forge repairs.
Management keys remain in Keychain, separate from HTML. Resource sessions are
supplied explicitly by frontend calls. The native host only sends runtime
requests to the linked app's API and excludes platform-internal paths.

Generated routes use backend.request({path,method,body,session}). The native
bridge supplies publicKey. Subscribe/unsubscribe bind the registered APNs token
to a resource session. The bridge never gives generated HTML management access.
Normal exports strip generated Python. V2 shares carry public connection
metadata, which imports as a participant link without a management key.
Deleting a participant app does not delete the owner's backend.

Existing v1 links remain supported. V2 changes do not auto-migrate v1 data.
Source patches flow through Forge's existing document patch machinery; the
resulting full bundle is deployed against the server's current revision.
Schema migrations, outbound domain policy and candidate readiness checks are
enforced by the runtime. Readiness checks do not prove all generated behavior.

## Verification and remaining release gates

Passed: source invariants, canonical native registry/SDK checks, native bridge
JavaScript, runtime foundation, widget and car display JavaScript checks.
Swift compilation could not run: swiftc and Xcode are unavailable here.
No GitHub Actions workflow was dispatched.

Before distribution, compile in Xcode and test two devices for generation,
resource isolation, client encryption/wrong-password behavior, offline retries,
process termination during deployment, participant sharing and APNs delivery.
Token rotation refresh and notification-to-app routing are implemented but need
real-device verification. Web Crypto availability in the actual WKWebView origin
and resumption after device process termination remain release validation gates.
Pending operations resume when the saved generation draft is reopened and saved.
A signed build is required for actual phone notification delivery.
The Hostish Screen agent still needs reboot startup configuration on the VPS.
