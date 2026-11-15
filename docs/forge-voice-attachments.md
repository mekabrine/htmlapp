# Voice attachments and durable app conversations — 1.9.16

While dragging the Library, running-app edit, or Forge edit microphone, three large targets appear at the top: Camera, Photos, and Files. Releasing on a target stops capture but defers Whisper decoding until selection is complete. Picker cancellation does not submit an AI request. A successful selection transcribes the captured request and submits it with the chosen references. A paperclip menu in Forge can remove references before a later request.

Up to four files/photos are accepted per selection. Camera capture accepts one photo. Images are normalized to JPEG at up to 1600px and sent as image content through the configured OpenAI-compatible or Anthropic message format. The selected model must support vision. Files accept UTF-8 text/code up to 160 KB per file and readable-text PDFs; originals must be under 8 MB. Image-only PDFs require page screenshots. Unsupported data produces an explicit error rather than sending just a filename. Text and PDF contents are included as reference data. Offline Forge accepts text references; image requests remain available for an online vision model.

Images can also be used as real app assets: the coding request names a stable attachment token, and the host embeds the selected JPEG into the generated HTML when that token is used. Request attachments are cached privately for background-result recovery and removed after saving or explicitly discarding the request; saved app images remain embedded in its HTML.

Question planning can return NO_QUESTION. Unresolved substantial choices get one question; ordinary design choices use defaults. Text changes, focus changes, and taps reset a five-second inactivity deadline. The current typed answer is used when nonempty, otherwise Forge's recommendation is used. Inactive/background transitions resolve a pending question immediately and allow the existing background request handoff. Background upload bodies include the same attachment inputs and history context. iOS suspension, force-quit, lost connectivity, and provider limits can still stop or delay work; foreground QA remains necessary after a background result.

App Conversation is available from Library → app menu → AI Edit History. It is an append-only JSONL log in Application Support/HTMLApp/ConversationLogs. Requests, bounded technical outcome summaries, questions/answers, saved and unsaved reverts, and completed export/nearby share events accumulate without automatic pruning. Recent bounded context informs subsequent edits. Share destinations are observations, not automatic evidence of user approval. Cancelled shares are not logged as completed shares. Private backups contain full conversation entries; nearby packages without personal data exclude them. Imports merge stable entry IDs to avoid duplication. Original attachment bytes are request inputs, not retained forever in this conversation log.

## Manual validation

- Exercise Camera, Photos, Files, cancellation, denied camera access, and unsupported/oversized files from each microphone entry point, with Apple Speech and Whisper.
- Verify the selected model receives image content and actual text/PDF contents; compare the generated change against the reference.
- While a question is visible, type repeatedly for more than five seconds. It must remain visible until five seconds after the final interaction. Then test idle timeout and locking mid-question.
- Confirm a locked-screen provider request can finish through the existing background path, and foreground verification resumes on reopening. Do not claim uninterrupted execution on all iOS versions.
- Save multiple edits, undo a draft, restore an older saved checkpoint, complete and cancel a share, restart HTMLApp, and inspect App Conversation.
- Export a private backup and restore it; verify original timestamps and IDs survive and repeated merges do not duplicate events. Confirm non-personal nearby exports contain no conversations.

Local source/bridge checks do not compile UIKit, PHPicker, SwiftUI, or native XCTest. Those checks require the user's manual build/device validation.

Image payload references: https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create and https://platform.claude.com/docs/en/build-with-claude/vision .
