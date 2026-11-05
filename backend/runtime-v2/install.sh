#!/bin/bash
# Install infrastructure, then require real sandbox tests before switching the public listener.
set -euo pipefail
cd -- "$(dirname -- "$0")"
if [ "$(id -u)" != 0 ]; then echo 'Run as root on the VPS.' >&2; exit 1; fi
systemctl is-active --quiet htmlapp-template-gateway.service
getent passwd htmlapp-gateway >/dev/null
test -x /opt/htmlapp-template-gateway/.venv/bin/gunicorn
test -f /etc/htmlapp-template-gateway.env
docker info >/dev/null
command -v runsc >/dev/null
if [ -e /etc/systemd/system/htmlapp-template-gateway.service.d/20-runtime-v2.conf ]; then
  echo 'Runtime gateway already enabled. Run smoke-test.py instead of reinstalling.' >&2
  exit 1
fi
# No removal of Docker, existing containers, the legacy database, or Hostish agent.
apt-get update
apt-get install -y xfsprogs util-linux iptables
install -d -m 0700 /var/lib/htmlapp-runtime
install -d -m 0755 /opt/htmlapp-runtime
install -m 0644 manager.py api.py service.py gateway_v2.py htmlapp_sdk.py worker.py FORGE-CONTRACT.md VERSION /opt/htmlapp-runtime/
install -m 0755 storage.sh admin.py smoke-test.py rollback.sh /opt/htmlapp-runtime/
install -d -m 0755 /opt/htmlapp-runtime/examples
install -m 0644 examples/* /opt/htmlapp-runtime/examples/
image='/home/htmlapp backend/backend-files/runtime-v2-storage.img'
if [ ! -e "$image" ]; then
  # Reserve one GiB so exhaustion of the host disk cannot silently defeat app quotas.
  available=$(df -B1 --output=avail '/home/htmlapp backend/backend-files' | tail -1)
  if [ "$available" -lt 1610612736 ]; then echo 'Need at least 1.5 GiB free.' >&2; exit 1; fi
  (umask 077; set -C; : > "$image")
  fallocate -l 1G "$image"
  mkfs.xfs -q "$image"
else
  if [ "$(blkid -p -s TYPE -o value "$image")" != xfs ]; then
    echo 'Existing storage image is not XFS. No formatting performed.' >&2
    exit 1
  fi
fi
# A distinct runtime name avoids changing other gVisor workloads.
runsc install --runtime htmlapp-runsc -- --overlay2=none --platform=systrap --network=sandbox --host-uds=none --host-fifo=none
systemctl reload docker
base=$(docker pull python:3.12-slim >/dev/null && docker image inspect --format '{{index .RepoDigests 0}}' python:3.12-slim)
docker build --build-arg "BASE_IMAGE=$base" -t htmlapp-python:v2 .
docker image inspect --format '{{.Id}}' htmlapp-python:v2 > /var/lib/htmlapp-runtime/image-id
install -m 0644 htmlapp-runtime-storage.service htmlapp-runtime.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now htmlapp-runtime-storage.service
systemctl enable --now htmlapp-runtime.service
systemctl restart htmlapp-runtime.service
# This tests real gVisor processes, quota enforcement, host/egress isolation,
# deployments, sessions, migration rollback and lifecycle using the local socket.
python3 /opt/htmlapp-runtime/smoke-test.py --local
install -m 0644 gateway_v2.py /opt/htmlapp-template-gateway/gateway_v2.py
install -d -m 0755 /etc/systemd/system/htmlapp-template-gateway.service.d
cat > /etc/systemd/system/htmlapp-template-gateway.service.d/20-runtime-v2.conf <<'EOF'
[Unit]
Wants=htmlapp-runtime.service
After=htmlapp-runtime.service
[Service]
ExecStart=
ExecStart=/opt/htmlapp-template-gateway/.venv/bin/gunicorn --bind 127.0.0.1:45806 --workers 1 --threads 8 --timeout 60 --limit-request-line 4096 --limit-request-fields 32 --limit-request-field_size 2048 gateway_v2:create_app()
EOF
restore_gateway() {
  echo 'Upgrade check failed. Restoring the legacy listener.' >&2
  rm -f /etc/systemd/system/htmlapp-template-gateway.service.d/20-runtime-v2.conf
  systemctl daemon-reload
  systemctl restart htmlapp-template-gateway.service
}
systemctl daemon-reload
if ! systemctl restart htmlapp-template-gateway.service; then restore_gateway; exit 1; fi
if ! curl -fsS --retry 5 --retry-connrefused --max-time 5 http://127.0.0.1:45806/health >/dev/null ||
   ! curl -fsS --retry 5 --retry-connrefused --max-time 10 https://htmlapp.hostish.site/v2/capabilities >/dev/null; then
  restore_gateway
  exit 1
fi
if ! python3 /opt/htmlapp-runtime/smoke-test.py; then restore_gateway; exit 1; fi
echo 'PASS: Runtime v2 installed and tested locally and through Hostish.'
echo 'Next step is HTMLApp client integration. Existing HTMLApp builds still use v1.'
