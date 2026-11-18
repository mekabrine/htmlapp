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
DELIVERY_DIR="$(mktemp -d)"
trap 'rm -rf "$DELIVERY_DIR"' EXIT
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDENTITY="$(python3 - "$DELIVERY_DIR" <<'IDENTITY_PY'
import json
import plistlib
import re
import sys
from pathlib import Path
from zipfile import ZipFile

directory = Path(sys.argv[1])
with ZipFile("HTMLApp.ipa") as archive:
    bundle = "Payload/HTMLApp.app"
    info = plistlib.loads(archive.read(f"{bundle}/Info.plist"))
    releases = json.loads(archive.read(f"{bundle}/HTMLApp-Changelog.json"))
version = info["CFBundleShortVersionString"]
build = str(info["CFBundleVersion"])
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) or not re.fullmatch(r"[0-9]+", build):
    raise SystemExit("Invalid packaged HTMLApp version or build")
release = next((entry for entry in releases if entry["version"] == version), None)
if not release or not release.get("changes"):
    raise SystemExit(f"Missing packaged What's New entries for {version}")
(directory / "release.json").write_text(json.dumps(release), encoding="utf-8")
notes = "\n\n".join(f"**{item['title']}**\n{item['description']}" for item in release["changes"])
(directory / "Whats-New.md").write_text(notes, encoding="utf-8")
print(f"{version} {build}")
IDENTITY_PY
)"
read -r VERSION BUILD <<< "$IDENTITY"
FILENAME="HTMLApp-${VERSION}_${BUILD}.ipa"
PREVIEW="Whats-New-${VERSION}.png"
MESSAGE="HTMLApp ${VERSION} (build ${BUILD}) attached. Install with TrollStore or re-sign with Feather."
UPLOAD_ARGS=(-F "files[0]=@HTMLApp.ipa;filename=$FILENAME;type=application/octet-stream")
IMAGE=""
NEXT_FILE=1
if command -v xcrun >/dev/null &&
   xcrun swiftc -parse-as-library "$SCRIPT_DIR/render-whats-new.swift" -o "$DELIVERY_DIR/render-whats-new" &&
   "$DELIVERY_DIR/render-whats-new" "$DELIVERY_DIR/release.json" "$BUILD" "$DELIVERY_DIR/$PREVIEW" &&
   test -s "$DELIVERY_DIR/$PREVIEW"; then
  IMAGE="attachment://$PREVIEW"
  UPLOAD_ARGS+=(-F "files[1]=@$DELIVERY_DIR/$PREVIEW;filename=$PREVIEW;type=image/png")
  NEXT_FILE=2
else
  echo '::notice::Release preview unavailable. Delivering the IPA and written release notes.'
fi

NOTES="$(cat "$DELIVERY_DIR/Whats-New.md")"
# Discord caps an embed description at 4096 characters. Keep all the text even
# for a larger release by attaching the complete Markdown notes in that case.
if [ "${#NOTES}" -gt 2000 ]; then
  UPLOAD_ARGS+=(-F "files[$NEXT_FILE]=@$DELIVERY_DIR/Whats-New.md;filename=Whats-New-$VERSION.md;type=text/markdown")
  NOTES="The full release notes are attached."
fi
PAYLOAD="$(jq -nc --arg content "$MESSAGE" --arg title "What’s new in $VERSION" --arg notes "$NOTES" --arg image "$IMAGE" '
  {content:$content,username:"HTMLApp Build Bot",allowed_mentions:{parse:[]},
   embeds:[({title:$title,description:$notes,color:10650862} +
     (if $image == "" then {} else {image:{url:$image}} end))]}')"
RESPONSE="$DELIVERY_DIR/discord-response.json"
UPLOAD="$(curl --silent --show-error --connect-timeout 15 --max-time 120 --output "$RESPONSE" --write-out '%{http_code}' --form-string "payload_json=$PAYLOAD" "${UPLOAD_ARGS[@]}" "$DISCORD_WEBHOOK_URL?wait=true")"
echo "Discord attachment HTTP $UPLOAD"
if [ "$UPLOAD" != '200' ]; then
  jq '{code: .code, errorFields: ((.errors // {}) | keys)}' "$RESPONSE" || true
  exit 1
fi
jq -e --arg filename "$FILENAME" 'any(.attachments[]; .size > 0 and .filename == $filename)' "$RESPONSE" >/dev/null
echo "Discord confirmed the $FILENAME attachment."
echo 'Discord IPA delivery completed directly with no webhook proxy.'
