# Integrated upgrade reconciliation — 1.6.31 (build 46)

This branch deliberately preserves the current mainline feature set while setting the requested release identity to 1.6.31 (46). It is a development build, **not** an independently verified release. The numeric downgrade from 1.6.38 does not undo the source-level features developed after 1.6.31.

## Confirmed from source inspection

- AI native methods and per-app AI permission, rate/usage data, global AI kill switch and compact-output setting exist.
- Vision image processing, NaturalLanguage, speech transcription, SQLite document store, Spotlight indexing, and Shortcuts dispatch handlers exist.
- The project uses XcodeGen with iOS 16 minimum, widgets and a manually dispatched GitHub Actions IPA workflow.
- Native Vision dispatch patterns duplicated in a NaturalLanguage switch case; this branch removes the duplicate and adds an invariant.

## Not established or missing relative to the requested specification

- AI token streaming callbacks and cancellable high-level JS streaming API; existing low-level cancellation does not expose a request ID through complete().
- iOS 26 Foundation Models preference/fallback verified on hardware.
- Live camera barcode scanning, the exact requested speech.recognize/stopRecognizing naming, and fully offline speech guarantees.
- HealthKit read APIs, NFC foreground NDEF, and a native MapKit presentation bridge.
- Stable per-app WKURLSchemeHandler origin, precache asset resolution, and old-origin web storage migration.
- Per-app arbitrary App Intents registration and Spotlight deep-link item callback semantics.
- Full where/orderBy/cursor query parity and selected-field full-text indexing.
- Prompt caching, measured speed gains, compact primitive inlining/fallback, seeded design-fingerprint sameness checks.
- Automated 3–5 flow replay, robust bridge feature-detection lint, and safe-area/responsive test matrix.
- Namespace-based bridge/service decomposition and comprehensive executable unit test coverage.

These capabilities must not be advertised as implemented solely because there is a related catalog entry. Do not remove unsupported capability warnings without corresponding executable and tested behavior.

## Required checks before shipping

1. Run `python3 scripts/test-source-invariants.py` and `node scripts/test-widget-bridge.js`.
2. Run XcodeGen and an Xcode 26 device build for iOS 16 minimum deployment; resolve warnings/errors.
3. Run widget simulator tests, test HTML bridge permission rejection, denied consent, malformed data, and app exit cancellation.
4. Verify backups and iCloud round-trip restore including SQLite data and existing key-value data.
5. Sign a device build and test widgets/App Groups, Spotlight/Shortcuts, camera/mic permissions, model fallback, and background limits.
6. Check prior localStorage and IndexedDB content before attempting any origin migration.
7. Record actual before/after Forge telemetry timings; no speed claim is supported without measurements.

Do not claim a passing build, installed IPA, migrated web storage, or real hardware support until verified independently.
