#!/usr/bin/env python3
"""Require a release identity bump for product changes.

Use [build-fix] in the commit subject only when a commit exclusively fixes a
build/CI/compiler/package failure and intentionally should not trigger What's New.
Use [no-version-bump] only for an owner-requested same-version update with release notes.
"""

from pathlib import Path
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / "HTMLAppV3" / "HTMLAppWhatsNewView.swift"

PRODUCT_PREFIXES = ("HTMLAppV3/", "HTMLAppShared/", "HTMLAppWidgets/", "HTMLApp/")
PRODUCT_FILES = {"project.yml"}
EXEMPT_SUBJECT_MARKER = "[build-fix]"
SAME_VERSION_MARKER = "[no-version-bump]"


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def identity(ref: str) -> tuple[str, str]:
    text = git("show", f"{ref}:HTMLAppV3/HTMLAppWhatsNewView.swift")
    version = re.search(r'static let compiledVersion = "([^"]+)"', text)
    build = re.search(r'static let compiledBuild = "([^"]+)"', text)
    if not version or not build:
        raise RuntimeError(f"Could not read release identity at {ref}")
    return version.group(1), build.group(1)


try:
    parent = git("rev-parse", "HEAD^")
except subprocess.CalledProcessError:
    print("Version-bump policy skipped: no parent commit available.")
    sys.exit(0)

subject = git("log", "-1", "--pretty=%s")
changed = [p for p in git("diff", "--name-only", parent, "HEAD").splitlines() if p]
product_changed = any(
    path in PRODUCT_FILES or path.startswith(PRODUCT_PREFIXES)
    for path in changed
)

# The policy script/workflows/docs can evolve without presenting What's New.
if not product_changed:
    print("Version-bump policy passed: no product source changed.")
    sys.exit(0)

if EXEMPT_SUBJECT_MARKER in subject.lower():
    print("Version-bump policy exemption accepted for explicit build-only fix.")
    sys.exit(0)

old_version, old_build = identity(parent)
new_version, new_build = identity("HEAD")

same_version = SAME_VERSION_MARKER in subject.lower()
if same_version and (new_version, new_build) != (old_version, old_build):
    raise SystemExit("A same-version update must keep both the version and build unchanged.")
if not same_version and new_version == old_version:
    raise SystemExit(
        f"Product source changed but compiledVersion stayed {new_version}. "
        f"Bump the release version and add What's New notes, or use "
        f"{EXEMPT_SUBJECT_MARKER} only for a build-error-only fix."
    )
if not same_version and new_build == old_build:
    raise SystemExit(
        f"Product source changed but compiledBuild stayed {new_build}. "
        "Increment the build identity with the release version."
    )

notes = re.findall(
    r'Entry\(id:\s*"[^"]+",\s*title:\s*("(?:\\.|[^"\\])*"),\s*description:\s*("(?:\\.|[^"\\])*")'
    r',\s*symbol:\s*"([^"]+)",\s*tint:\s*\.(\w+)',
    git("show", "HEAD:HTMLAppV3/HTMLAppWhatsNewView.swift"),
)
expected_changes = [{"title": json.loads(title), "description": json.loads(description),
                     "symbol": symbol, "tint": tint}
                    for title, description, symbol, tint in notes]
changelog = json.loads(git("show", "HEAD:HTMLApp/Resources/HTMLApp-Changelog.json"))
if (not expected_changes or not changelog or changelog[0]["version"] != new_version
        or changelog[0].get("changes") != expected_changes):
    raise SystemExit("Archive every current What's New title, description, symbol and tint in the newest changelog entry.")

if same_version:
    if git("show", "HEAD:HTMLAppV3/HTMLAppWhatsNewView.swift") == git("show", f"{parent}:HTMLAppV3/HTMLAppWhatsNewView.swift"):
        raise SystemExit("A same-version product update must refresh What's New.")
    print(f"Same-version update verified: {new_version} ({new_build}).")
    sys.exit(0)

print(
    f"Version-bump policy passed: {old_version} ({old_build}) -> "
    f"{new_version} ({new_build})."
)
