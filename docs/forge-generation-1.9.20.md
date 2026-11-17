# Forge generation and dictation — 1.9.20 (125)

The voice provider described below is historical. Version 1.9.21 replaces it
with free keyless NoteTakers transcription; see [current voice behavior](forge-keyless-transcription-1.9.21.md).

After a foreground initial generation (including a completed background result
restored into Forge), a sheet offers one more UI review. No is selected after
five seconds. Dismissal, backgrounding and cancellation decline the review.
Explicitly accepting uses the UI specialist or the normal configured provider.
Exact patches preserve scripts and pass the data/navigation safety gate before
verification; failed verification restores the original draft and QA report.
Focused edits do not trigger an additional redesign. Practice and on-device-only
generation do not submit a cloud UI review.

Forge's implementation contract now emphasizes outcome tracing, state ownership,
focused edits, cached evidence and purposeful touch gestures with accessible
alternatives. Normal first-party GPT-5/6 requests use medium reasoning; QUICK!
retains its low-reasoning option. This is not a measured quality or speed claim.

The bundled guide retains the uploaded guide's full reference format and now
contains the current 186-method schema, generated TypeScript declarations,
168-entry API discovery catalog, runtime/backend contracts, Control Center and
richer Live Activity guidance. It explicitly describes the currently disabled
hosted-backend feature. The guide is shared/exported separately; its full API
appendix is not added to every model request.

Symbol discovery supports topic queries and an expanded set of candidates and
variants, filters each against the installed OS, and returns up to 200 matches.
Rendering also validates names. Unsupported candidates are never returned.

New widget refresh specifications and default timelines request 15 minutes
instead of 30. Existing explicit intervals are preserved. Due data refreshes
also run at launch/resume. Snapshot changes still request coalesced reloads.
iOS controls actual scheduling; this cannot guarantee 15-minute delivery.

## Voice setup

Settings → AI & Voice exposes Alternative (retaining the old `whisper` storage
value) and a Forge-only online-transcription switch and secure Groq key field.
With a personal key and the switch enabled, generation/edit recordings use
Groq's `whisper-large-v3-turbo` transcription endpoint, regardless of the saved
Apple/Alternative engine preference. This uploads audio; the setup copy says so.
Groq has a rate-limited free tier; account-plan billing terms still apply.

Recordings are bounded to five minutes. Upload uses 16 kHz mono WAV, a 25 MB
limit, an ephemeral no-cookie session, no redirects, and request/resource
timeouts. Non-2xx, malformed and empty transcripts fall back to local decoding.
Terminal failures keep the recording for retry. Explicit cancellation cancels
the request, invalidates its generation and discards audio. Saved apps construct
`ForgeDictation(allowsOnlineTranscription: false)` and never inherit cloud upload
permission. Without online setup, Apple/on-device dictation remains available.

Official service contract: https://console.groq.com/docs/speech-to-text
Free-plan quotas: https://console.groq.com/docs/rate-limits

## Validation

Offline source, native bridge, widget, runtime and catalog checks can run on
Linux. The guide's embedded schema/types/catalog are checked against repository
sources. New XCTest transport tests cover successful text, authentication/quota/
server failures, invalid payloads, missing credentials and invalid audio sizes
without real recordings or API calls. They are included in HTMLAppWidgetTests
and require Xcode to execute. An iOS build and real-device microphone, countdown
sheet, widget scheduling and network fallback checks remain necessary.
