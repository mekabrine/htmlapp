# Everyday app experience

This change implements six product improvements around creating, trying, refining, and using HTMLApps. It builds on the existing draft checkpoints, permission gate, edit history, favorites and portable backups.

## What changes

| Area | User-facing behavior | Main implementation |
| --- | --- | --- |
| First useful app | Onboarding links directly to Forge. Pocket Expenses, Focus Timer and Workout Notes can be tried and saved without a provider. Each also supplies an editable idea. | `ForgeStarterApps.swift`, `ForgeExperience.swift`, `OnboardingSettings.swift` |
| Understandable progress | Planning / Building / Checking / Ready stages sit above the existing dashboard. A failed run retains its draft and offers actionable retry/provider guidance. Save failures keep the studio open. | `ForgeExperiencePolicy.swift`, `AIGenerationView.swift` |
| Confident editing | Compare before and after without saved native data access. Edit History & Undo is available from Everyday Usage. Earlier checkpoints can be previewed before restoring. | `HTMLAppEditHistoryView.swift`, `ForgeExperience.swift`, `LibraryUI.swift` |
| Daily use | A root-library shelf opens up to four favorites and four other recently used apps, including apps in folders. Search and folder layouts retain their existing behavior. | `HTMLAppQuickAccess`, `LibraryUI.swift` |
| Contextual permission | Native, location and motion consent prompts identify the requesting app, explain the capability, and describe declining or changing the choice later. | `PermissionSystem.swift`, `LocationPermissionBridge.swift`, `EditorWeb.swift` |
| Trustworthy sync | Settings and Backup & Transfer show check time, errors and pending changes. Different edits on both sides require review. Review includes source previews and saved-data excerpts. Local recovery ZIPs precede replacements. | `HTMLAppICloudSync.swift`, `HTMLAppSyncMergePolicy.swift`, `HTMLAppSyncReview.swift`, `AppCore.swift` |

## Data and recovery behavior

- Starter trials keep entries in memory. Saving creates a clean app; the preview's trial entries are not copied. Saved starters use the existing per-app portable storage bridge and handle failed writes without changing the committed view.
- Focus Timer uses a saved end time to recover elapsed time after reopening. It does not claim background alarms, notifications, or Live Activities.
- Version previews use the `PREVIEW` identity. Code restores retain portable user data and checkpoint the current source; they do not undo migrations or data changes made by an app while running.
- Sync compares local/cloud fingerprints against the last synchronized snapshot. Ordinary one-sided edits sync automatically; divergent edits and differing pre-existing copies without a baseline require a decision. Empty data snapshots count as edits.
- Choosing a sync version checks that the reviewed local version and locally available cloud documents have not changed. File coordination protects each document; iCloud remains eventually consistent and the operation is not a cross-document transaction.
- A sync replacement first creates a local portable recovery package. The ten most recent recovery packages are retained. Export the latest under Backup & Transfer → Sync Recovery Backups; restore with Merge as New Copies to inspect it safely.
- Check time means a completed local iCloud file exchange, not confirmation that another device has downloaded every change. Unreadable or pending documents are reported and left untouched.
- Backup status says "prepared" because the app cannot know whether the user completed the external share-sheet save.
- Folder merge behavior remains the existing additive merge. Folder rename/deletion reconciliation is a separate follow-up, rather than being implied by the new source/data conflict review.

## Validation

Runnable without Xcode:

```sh
python3 scripts/test-source-invariants.py
node scripts/test-widget-bridge.js
node scripts/test-starter-apps.js
```

The starter checks execute the exact bundled JavaScript against a minimal DOM and the native storage serialization contract. They cover persisted purchases/workouts, input validation, removal/undo, timer pause/reopen/completion, failed saves, corrupt saved state, and trials that never write personal data. They do not replace rendering or touch testing in WebKit.

`HTMLAppWidgetTests/ExperiencePolicyTests.swift` adds executable Swift tests for one-sided and conflicting sync edits, explicit clears, stable fingerprints, failed-build stage selection, and trial document isolation. These are included in the existing simulator test target. On macOS, generate the project with `xcodegen generate` and run `bash scripts/test-widgets.sh`; use an installed eligible simulator and confirm tests actually ran. The manual IPA workflow also runs the starter JavaScript tests. Its optional simulator-test input includes the experience policy tests.

No iOS build, simulator run, or two-device iCloud test has been performed in the editing environment, which has no Xcode. Before merging:

- Build the app and tests with Xcode 26; exercise the supported deployment targets.
- Try all starters on a narrow iPhone and iPad, with VoiceOver and larger text. Save, close, reopen, and check persisted entries. Confirm trial entries are discarded when saved.
- Simulate a provider/network failure; dismiss the alert, inspect the preserved draft, adjust settings, retry, compare, and undo an edit.
- Verify quick access after favoriting, opening an app from a folder, and searching.
- Request and decline location, motion, Health, clipboard and contacts from two named apps. Check consent remains scoped per app.
- With two iCloud devices, test one-sided edits, divergent code edits, divergent saved entries, explicit clears, pending downloads, offline/account failures, stale review choices, and recovery ZIP import.
