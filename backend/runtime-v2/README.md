# HTMLApp Runtime v2 VPS upgrade — release candidate

This package adds real generated Python deployments to your existing Hostish
VPS gateway. The current HTMLApp 1.7.3 still uses v1 and needs a separate client
update before it can generate or deploy these backends.

Docker and runsc are already installed on your Ubuntu 24.04 VPS. Installation
requires root, the existing htmlapp-template-gateway.service, its virtualenv,
and /etc/htmlapp-template-gateway.env. Leave your Hostish Screen agent running.

## Install

Upload htmlapp-runtime-v2.zip to /root, then run:

```bash
cd /root
python3 -m zipfile -e htmlapp-runtime-v2.zip .
bash /root/htmlapp-runtime-v2/install.sh
```

The installer uses the official gVisor runtime you already installed. It creates
a separate htmlapp-runsc configuration, resolves the Python image to a digest,
installs the SDK into a fixed image, and starts a root-only lifecycle manager.
The unprivileged public gateway forwards v2 to a local Unix socket. Generated
code runs only inside gVisor, never in the root manager or public gateway.

A one-GiB preallocated XFS volume is stored at:
/home/htmlapp backend/backend-files/runtime-v2-storage.img
It mounts at /var/lib/htmlapp-runtime/workspaces via a systemd storage service.
App source/data are physically stored inside that image. Each 12-character app
ID has its own quota-controlled directory and versioned Python source/data.
The main ext4 filesystem is not reformatted or remounted. There is no host /etc
filesystem-quota reconfiguration. Keep the volume image and root state together
when making backups. Never copy a mounted live image as a consistent backup.

The workspace cap is 1952 KiB (1998848 bytes), below the requested 2 MB ceiling.
It includes staged copies, so updates require space for old and candidate data.
The Python/crypto runtime image, administrative metadata, capped 64 KiB Docker
logs, and bounded notification queue are separate infrastructure storage.
Six active apps globally and three per enrollment secret are the initial limits.
These are explicit conservative limits for the current one-CPU, 4 GiB VPS.

Before enabling public v2, the installer runs real Docker/gVisor tests against
the private socket. It checks scopes, shared sessions, persistent events,
creation retries, filesystem quota, network restrictions, failed deployments,
data-preserving rollback, manager restart and repeated deletion. If that test
fails, it exits before changing the current public listener. It then enables a
small service override and repeats checks through Hostish. A public test failure
restores the original gateway entrypoint. Temporary test apps are cleaned up.

The existing v1 gateway database and APIs remain available. The installer
reloads Docker configuration and restarts the public gateway
only after the local runtime tests pass. No Hostish agent.py modification is
needed. Runtime processes restore after reboot; the existing Screen-based
Hostish agent still needs its existing startup method. This package cannot
safely infer or install its credentials/launch arguments as a systemd unit.

## Verify and diagnose

```bash
systemctl status htmlapp-runtime-storage htmlapp-runtime --no-pager
curl -fsS https://htmlapp.hostish.site/v2/capabilities
python3 /opt/htmlapp-runtime/smoke-test.py
journalctl -u htmlapp-runtime.service -n 60 --no-pager
```

Local tests require one temporary free deployment slot. Avoid concurrent
smoke-test runs, especially because the local test restarts the runtime manager.
A lost creation response can be recovered using the same clientID. Mutation
operations have explicit IDs and polling endpoints. Never paste secrets into
chat or include full container inspect output/environment in shared logs.

The test does not prove a sandbox is invulnerable. It verifies essential policy
configuration and attempts forbidden network/storage access. Review runtime
updates and maintain Docker/gVisor/Ubuntu security updates. Do not grant scripts
Docker access, add arbitrary mounts, use privileged mode or disable gVisor.

## Secrets and device notifications

Your existing HTMLAPP_PROVISION_KEY works for initial v2 enrollment. It creates
backends and can recover an app's credentials with that app's original clientID.
Use separate secrets for trusted people, issued locally on the VPS:

```bash
python3 /opt/htmlapp-runtime/admin.py issue-secret --label 'Family' --max-apps 2
python3 /opt/htmlapp-runtime/admin.py list-secrets
python3 /opt/htmlapp-runtime/admin.py revoke-secret --fingerprint FULL_HASH_FROM_LIST
```

Revocation blocks creation and credential recovery via that enrollment secret.
It does not delete existing apps or rotate their per-app management/runtime keys.
For a compromised per-app key, rotate locally (prints new credentials privately):

```bash
python3 /opt/htmlapp-runtime/admin.py rotate-app-keys --app-id TWELVECHARID
```

Existing clients must receive the new publicKey and the creator must replace
its local managementKey. Future HTMLApp integration must handle this flow.

APNs reuses the existing APNS_TEAM_ID, APNS_KEY_ID, APNS_TOPIC, APNS_KEY_PATH and
APNS_SANDBOX in /etc/htmlapp-template-gateway.env. The .p8 file remains on the VPS.
Without these, custom backends still run but push delivery reports unavailable.
The test never claims APNs delivery passed without a real signed phone/device.
The SDK supports multiple device/resource subscriptions and a bounded durable
push queue. Actual iOS registration, signing and permission are client work.

## Roll back to v1

```bash
bash /opt/htmlapp-runtime/rollback.sh
```

This stops labeled v2 workloads, disables their manager, removes the gateway
service override, and restarts the existing v1 gateway. It preserves the volume,
metadata and keys. It does not delete your original gateway or its database.

To re-enable an installed runtime after rollback, first start its manager and
run the local smoke test, then rerun install.sh to restore the gateway override.
Do not reinstall while the v2 override is already enabled.

## Acceptance status

Workspace tests exercise SDK behavior, the real HTTP worker, session persistence,
transactional migration failure, manager state transitions, permissions,
path traversal, link-safe copying, revision conflicts and operation retries.
They do not execute untrusted source on the host. The manager tests use a fake
Docker engine because the build workspace has no Docker daemon. The bundled
installer is the required actual-VPS Docker, firewall and quota verification.

This is an installation candidate, not a claim of a verified live deployment.
After the installer reports PASS, send its output so failures can be corrected
before HTMLApp integration. Keep the installer transcript free of secrets.
Read FORGE-CONTRACT.md for exact URLs, payloads, SDK behavior and limitations.
End-to-end group encryption, invitations, native sharing policy and Forge
frontend/backend generation are future HTMLApp integration work.
