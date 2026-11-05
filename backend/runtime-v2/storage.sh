#!/bin/bash
set -eu
image='/home/htmlapp backend/backend-files/runtime-v2-storage.img'
workspace='/var/lib/htmlapp-runtime/workspaces'
case "${1:-}" in
  mount)
    test -f "$image"
    install -d -m 0755 "$workspace"
    if ! mountpoint -q "$workspace"; then
      mount -t xfs -o loop,prjquota,nodev,nosuid,noexec "$image" "$workspace"
    fi
    test "$(findmnt -n -o FSTYPE --target "$workspace")" = xfs
    xfs_quota -x -c 'state -p' "$workspace" | grep -q 'Enforcement: ON'
    ;;
  *) echo 'Usage: storage.sh mount' >&2; exit 2 ;;
esac
