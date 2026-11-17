# First transcription per launch — 1.9.22 (127)

With online transcription enabled, the first eligible creation/edit recording
after a fresh HTMLApp process launch can use the free NoteTakers API. Subsequent
recordings use the selected Apple Speech/Alternative engine. The allowance is
shared across Library voice creation, Lock Screen entry, Forge and editor voice
edits, rather than being recreated for each view or dictation object.

The main-actor-isolated shared session claims its one attempt immediately before
awaiting the transport. Failures and cancellation after claiming still count;
saved-audio retries use the existing on-device path. Permission denial, cancelled
capture, empty/invalid recordings and a disabled online setting do not consume
the allowance. Backgrounding, returning to a recording screen, or toggling the
setting off/on cannot restore a consumed allowance. A fresh process launch does.

Onboarding/practice dictation and saved-app speech do not use the online path or
consume this allowance. When the allowance is exhausted, normal offline-model
preloading and Lock Screen warm-up are available again for Alternative.

Source checks verify shared actor isolation, claim-before-await ordering,
cancellation checks, practice exclusion and local preload routing. XCTest covers
single-use claims, disabled-setting behavior and a fresh launch's allowance.
XCTest and device lifecycle checks require Xcode and have not been run here.
Only local source checks are run; no workflows are dispatched.
