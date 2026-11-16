# Attachment requests and paused backends — 1.9.18 (123)

## Research

Requests with attachments enter browser research even when the normal fast path
would skip it. The researcher receives bounded text excerpts (up to 3,500
characters per file) and image inputs through the configured research model.
It may take up to four search/open/catalog actions, stopping earlier when its
evidence is sufficient. Ordinary requests retain their one-action budget.
Attachment research avoids reusing an attachment-free style preflight report.
Private attachment contents are reference data for the model, not instructions;
the researcher is directed to use generic technical search terms rather than
personal document contents, filenames or secrets. Web tools receive generated
queries/URLs, not uploaded attachment bytes. A research model/provider still has
to be configured and support the supplied inputs; unavailable research does not
prevent the existing generation fallback.

## Presentation and cleanup

The review owns a local picker target, independent of the microphone's initial
picker request. Camera authorization finishes before presenting its picker;
rapid duplicate taps are disabled while preparing the presentation. Missing
hardware and denied camera access produce an error rather than silently closing
the review. Cancelling an additional picker keeps the current review intact.

Generate snapshots the edited prompt and references, clears the source draft,
and passes that snapshot to the existing creation/edit pipeline only after the
review has dismissed. It does not retry transcription or read a cleared shared
selection in an asynchronously scheduled callback. Cancel clears the draft.

Successful completion clears the visible selection and private request cache.
Stop, discard, offline cancellation and recovered background completion have the
same cleanup. A job identity prevents late cleanup from an older cancelled task
from clearing references belonging to a new request. An active background upload
keeps its recovery references until its result can be materialized. Failed
requests retain references for retry. Service inputs are local to each task;
later calls cannot inherit a previous service input array. Images already embedded in generated HTML remain app assets;
originals in Photos/Files are never deleted by attachment cleanup.

## Backends paused

`HTMLAppBackendFeature.enabled` is false. Backend completeness requirements,
planner/authoring instructions, detailed runtime documentation, backend entries
in the native research catalog and backend methods in the coder's type catalog
are not offered as available capabilities. The planner is instructed to report
that hosting is unavailable and avoid fabricating server-dependent behavior.

The native capability list omits backend methods and calls reject with
`backend_disabled`. Central backend HTTP requests and deployment are gated;
automatic provisioning, deletion queues and subscription refresh do not run.
Saving an app skips backend extraction/deployment, so an existing inactive
bundle is not a new save-time requirement. Widget time checks remain active.
Backend settings/panels show the temporary pause. Source files, saved links,
credentials and existing pending work remain in place for a future repair.

## Device validation (manual build required)

1. On iOS 16.2 and iOS 26, enter review from each microphone source. Repeatedly
   add Camera, Photos and Files, including after cancelling each nested picker.
   The review must remain visible and the requested picker must open. Verify a
   denied camera permission produces the Settings guidance. Real hardware,
   permissions and UIKit presentation cannot be guaranteed by source checks.
2. Mix photos, a PDF and text, edit the prompt, and Generate once. Confirm the
   chosen model receives the edited request and references, research can open
   documentation after searching, and the next request has no old attachments.
3. Cancel review, Stop generation, and discard edits; then start a fresh request.
   Confirm no old attachments appear or remain in ForgeRequestAttachments.
   Stop and immediately create another request to exercise late-task cleanup.
4. Complete offline text generation and a background result. Verify references
   clear on completion, generated embedded images still work, and a failed
   request can still retry with its references.
5. With an existing backend link, open Settings and the app Backend panel.
   Confirm only the pause notice is available, no jobs/network requests run,
   backend feature detection is false, and a direct bridge call rejects clearly.
   Generate/save a local app and edit an old backend app without deploying,
   deleting its bundle, or demanding runtime repair. Verify local notifications,
   widgets and other native bridges still function.

Local source, generated-contract and JavaScript checks are not a SwiftUI build
or a device presentation test. No GitHub workflow is started by this validation.
