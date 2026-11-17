# Keyless Forge transcription — 1.9.21 (126)

Version 1.9.22 limits the online API to the first eligible transcription per
process launch; see [current launch policy](forge-first-transcription-1.9.22.md).

Forge now uses the public NoteTakers REST API by default for generation and edit
recordings. No signup, API key, account billing or payment setup is involved.
The former Groq configuration and key field are removed. Settings retains the
online-transcription switch and clearly identifies the recipient of uploaded
audio. Turning the switch off uses the selected Apple/Alternative engine.

## Service contract

- Endpoint: `POST https://notetakers.vipresearch.ca/stt/v1/transcribe`
- Multipart fields: `file` (WAV) and `engine=whisper`; language is auto-detected.
- Response: JSON with `success: true` and nonempty `text`.
- No Authorization header, API key or cookie.
- Free allowance: **10 requests/day per IP**, potentially shared across a network.
- No spoofed Origin, IP rotation, alternate endpoints or website exemptions.
- On HTTP failures, quota limits, busy responses, timeouts, malformed JSON,
  `success:false`, or empty text, use the original recording for on-device
  transcription. No automatic repeated online attempts or paid fallback.
- The host still limits recordings to five minutes and uploads to 25 MB, uses
  request/resource timeouts, refuses redirects and ignores cancelled/stale work.
- Saved apps explicitly disable the Forge online path; their speech permissions
  and Apple/on-device behavior remain independent.

Official API and limits: https://notetakers.vipresearch.ca/stt_docs.php

## Verification

On November 17, 2026, a direct unauthenticated health request returned status ok
and Whisper ready. One keyless multipart upload of locally synthesized,
nonpersonal 16 kHz mono speech returned HTTP 200 with `success:true` and text.
The synthetic prompt was “Build a daily habit tracker with reminders”; the
service returned “Build the daily habitat tracker with reminders.” This verifies
the endpoint/fields/response contract, not perfect accuracy or general latency.
The service reported 1.34 seconds of processing for 2.89 seconds of audio.

Transport XCTest fixtures now include the success flag, reject service failure
even on HTTP 200, and assert that no Authorization header is sent. Source checks
protect the keyless transport and independent saved-app upload policy. These
XCTest cases require Xcode and have not been executed in this Linux workspace.

PR #12 was merged at the owner's request. Further changes are committed directly
to main. All workflows remain manual-only, and no workflows were dispatched or
rerun. The standing main-only/no-workflow policy is recorded in AGENTS.md.
