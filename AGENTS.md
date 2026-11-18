# Release updates

Work only on `main`. Do not create feature branches or pull requests unless the
owner explicitly changes this instruction. Merge any existing pull request only
when the owner asks.

Never dispatch, rerun, or otherwise start GitHub Actions workflows unless the
owner explicitly asks. Keep workflows manual-only; commits and merges must not
add automatic triggers. Local checks are permitted.

For every product update, unless the owner explicitly asks otherwise, increment both the
marketing version and build number in `project.yml` and synchronize
`HTMLAppReleaseNotes.compiledVersion` and `compiledBuild`. Replace the What's New
entries with short, user-facing notes about that update. Archive every title, description, symbol and tint from What’s New, plus a one-line summary
for the new version in `HTMLApp/Resources/HTMLApp-Changelog.json`, newest first.

For a change that only fixes a build, compiler, CI, or packaging error, keep the
version, build number, and What's New entries unchanged. Mark that commit with
`[build-fix]` so the existing version policy check recognizes the exception.
