# Forge backend reliability: 1.8.1 (100)

The supplied recording requests an API that delivers messages to the phone.
Forge instead marks an on-device notification demo ready and says a public API
is unavailable. Relay's source declares unsupported `managed` metadata, omits
Python/manifest artifacts, and calls routes with no corresponding server code.
The VPS secret cannot repair a missing deployment artifact.

## Changes

- Planner explicitly classifies server requirements. The requirement survives
  draft restoration and applies regardless of optional fast/skip QA settings.
- Planning, coding, edits and capability lookup use the same real runtime v2
  capabilities. The bundled contract no longer asks for separate artifacts that
  the HTML response parser would discard.
- An unconditional completeness gate requires the source/manifest bundle,
  frontend runtime integration and matching literal routes. Up to two focused
  code repairs are attempted; failure blocks Ready and Save instead of silently
  accepting a local substitute. Server candidate checks still run on Save.
- Bundle parsing accepts reordered/extra attributes and case variants, rejects
  duplicates and validates required route/check structure. Export removes the
  same recognized script formats so case changes cannot expose Python source.
- V2 backend status queries the server and returns the real API URL, runtime
  version, state and APNs configuration instead of testing a legacy send key.
- Developer Backend can connect an existing bundle with the saved secret or
  open Forge to repair missing backend code. Legacy JSON linking is advanced.

`push.register` is a real native method, but only obtains an APNs device token.
It does not generate a server or register a resource subscription. The earlier
claim that the method itself did not exist was incorrect. V2 apps should use
backend.subscribe(session) for the host-managed resource subscription.

## Validation

Run scripts/test-forge-backends.py for mandatory-gate source regressions and
production Foundation behavior cases when swiftc is installed. The cases cover
the recording's local fallback, legacy managed marker, offline/public-weather
apps, semantic backend requirements, valid/reordered/uppercase bundles, missing
routes and duplicate artifacts. No live AI provider calls are claimed by these
checks.

The runtime worker regression exercises authenticated notification delivery to
a test broker, unauthorized rejection, resource scoping and session exclusion.
Actual APNs delivery still requires a signed iPhone build and server credentials.
The container has no swiftc/Xcode: Foundation behavior and iOS compilation are
reported as not run, rather than passed. No workflow is run automatically.
The production VPS does not need a reinstall for these HTMLApp changes.
