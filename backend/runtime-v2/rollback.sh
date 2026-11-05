#!/bin/bash
set -eu
if [ "$(id -u)" != 0 ]; then echo 'Run as root.' >&2; exit 1; fi
# Stop generated workloads before disabling their manager.
docker ps -aq --filter label=htmlapp.runtime=v2 | while read -r container; do
  test -z "$container" || docker stop --time 5 "$container"
done
systemctl disable --now htmlapp-runtime.service
rm -f /etc/systemd/system/htmlapp-template-gateway.service.d/20-runtime-v2.conf
systemctl daemon-reload
systemctl restart htmlapp-template-gateway.service
curl -fsS --retry 5 --retry-connrefused --max-time 3 http://127.0.0.1:45806/health
printf '\nLegacy gateway restored. Runtime source, app data and keys remain on disk.\n'
