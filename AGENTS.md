# Release updates

For every product update, unless the owner explicitly asks otherwise, increment both the
marketing version and build number in `project.yml` and synchronize
`HTMLAppReleaseNotes.compiledVersion` and `compiledBuild`. Replace the What's New
entries with short, user-facing notes about that update.

For a change that only fixes a build, compiler, CI, or packaging error, keep the
version, build number, and What's New entries unchanged. Mark that commit with
`[build-fix]` so the existing version policy check recognizes the exception.
