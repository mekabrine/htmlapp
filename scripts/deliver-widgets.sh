#!/bin/bash
set -euo pipefail
if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo '::notice::Discord IPA delivery skipped: DISCORD_WEBHOOK_URL is not configured; the GitHub IPA artifact remains available.'
  exit 0
fi
echo "::add-mask::$DISCORD_WEBHOOK_URL"
case "$DISCORD_WEBHOOK_URL" in
  https://discord.com/api/webhooks/*|https://discordapp.com/api/webhooks/*) ;;
  *) echo 'Invalid Discord webhook secret.'; exit 1 ;;
esac
# Read the identity from the exact verified IPA being sent.
test -s HTMLApp.ipa
IDENTITY="$(python3 - <<'IDENTITY_PY'
import plistlib
import re
from zipfile import ZipFile

with ZipFile("HTMLApp.ipa") as archive:
    info = plistlib.loads(archive.read("Payload/HTMLApp.app/Info.plist"))
version = info["CFBundleShortVersionString"]
build = str(info["CFBundleVersion"])
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) or not re.fullmatch(r"[0-9]+", build):
    raise SystemExit("Invalid packaged HTMLApp version or build")
print(f"{version} {build}")
IDENTITY_PY
)"
read -r VERSION BUILD <<< "$IDENTITY"
FILENAME="HTMLApp-${VERSION}_${BUILD}.ipa"
MESSAGE="HTMLApp ${VERSION} (build ${BUILD}) attached. Install with TrollStore or re-sign with Feather."
PAYLOAD="$(jq -nc --arg content "$MESSAGE" '{content:$content,username:"HTMLApp Build Bot",allowed_mentions:{parse:[]}}')"
UPLOAD="$(curl --silent --show-error --connect-timeout 15 --max-time 120 --output discord-delivery-response.json --write-out '%{http_code}' --form-string "payload_json=$PAYLOAD" -F "files[0]=@HTMLApp.ipa;filename=$FILENAME;type=application/octet-stream" "$DISCORD_WEBHOOK_URL?wait=true")"
echo "Discord attachment HTTP $UPLOAD"
if [ "$UPLOAD" != '200' ]; then
  jq '{code: .code, errorFields: ((.errors // {}) | keys)}' discord-delivery-response.json || true
  rm -f discord-delivery-response.json
  exit 1
fi
jq -e --arg filename "$FILENAME" 'any(.attachments[]; .size > 0 and .filename == $filename)' discord-delivery-response.json >/dev/null
rm discord-delivery-response.json
echo "Discord confirmed the $FILENAME attachment."
echo 'Discord IPA delivery completed directly with no webhook proxy.'
