# Forge generation and edit reliability — 1.6.76 (84)

## Problems addressed

- Non-streaming completions and background responses accepted text even when the provider reported token-limit truncation. Streams did not distinguish an abrupt EOF from completion.
- Cancellation during retry delay was swallowed, and optional planner fallbacks could continue after cancellation.
- Substring matching interpreted `ble` inside ordinary words such as `readable` as Bluetooth. Generic component words and duplicate IDs inflated targeting confidence.
- Patch sanitization discarded an unfinished final block. This could turn an incomplete multi-block edit into an apparently successful partial edit. Marker-like text within JavaScript strings could also be parsed as a delimiter.
- Visual preservation guarded native integrations using a separate narrow keyword list; words such as `remove` disabled that protection even for "remove the shadow." Screens and routes were not checked.
- The generator received the planner expansion without the literal request alongside it.

## Implementation

1. A shared Foundation-only response guard rejects token/context limits, refusals/content filtering and error envelopes. Foreground and background completion paths use it. Streaming requires a terminal provider event or `[DONE]`; interrupted generation still uses the existing continuation/recovery path, rather than marking the transport successful.
2. Cancellation checks run before/after provider throttling and after completion. Retry sleep now propagates cancellation. Prompt/refinement fallbacks propagate cancellation rather than continuing generation.
3. Generation, continuation and edit prompts retain the original request explicitly above advisory planner guidance. Product instructions now cover short-prompt assumptions, complete repeatable workflows, keyboard/sheet behavior, native affordances, accessibility, write ordering, stale async results, persistent-data validation and failure recovery. These are instructions to the configured model, not new native APIs or a measured model-quality guarantee.
4. Edit interpretation uses word boundaries, ranks exact IDs over token matches, deduplicates targets, recognizes short identifiers, ignores generic UI words and lowers confidence for tied matches. Bluetooth acronym matching is corrected in both scope and capability inference.
5. Focused excerpts are limited to confident local appearance/copy/component edits. Functional, architectural and ambiguous changes keep the full source. `data-forge-screen` becomes a supported excerpt anchor.
6. Patch parsing uses line-delimited states and rejects incomplete, malformed or trailing blocks atomically. Empty replacements remain supported, and marker text embedded in a code line is preserved. Existing unique-match safeguards and bounded repair attempts remain in place.
7. Visual/copy/accessibility edits use the same scope interpreter for preservation checks. Removed screens, routes and native methods are rejected alongside existing storage-key/collection checks. These are conservative source-level checks, not proof of runtime data safety.
8. Added Swift regressions for target ranking/ambiguity, BLE false positives, semantic excerpts, visual preservation, provider completion and atomic patch application. The macOS iOS verification workflow runs both suites; test-file-only changes also trigger it.
9. Updated project version and in-app What's New to 1.6.76 (84).

## Validation

Passed locally: source invariants; runtime foundation cancellation/data/migration/lifecycle checks; native bridge/viewport JavaScript; widget bridge; car-display JavaScript; bridge/Forge architecture checks (148 native methods).

Swift regression execution and the unsigned iOS build are delegated to the repository's macOS GitHub Actions workflow because the editing environment has no Swift compiler or Xcode. See the commit's check results for their actual outcome. No live provider calls, paid generation benchmarks, signed IPA or physical-device tests were performed here.

## Device/provider acceptance checks

Use the same configured model, settings and prompt set before/after; compare multiple runs. Measure successful workflows and edit preservation, not just appearance.

| Prompt / scenario | Expected observation |
| --- | --- |
| `habit tracker` | Working creation, daily completion, editing, durable history and honest empty states. |
| `notes app, offline only, no accounts` | Planner expansion preserves offline/no-account constraints; notes survive relaunch. |
| `make text readable please` | No Bluetooth research or permission added. |
| `make #weekly-card smaller` | Specific target changed; other cards and stored records retained. |
| `make weekly smaller` with several weekly components | Lower-confidence interpretation uses full source rather than arbitrarily choosing an excerpt. |
| `remove the shadow and make it cleaner` | Routes, screens and native integrations preserved. |
| `make it feel like iOS` | Appropriate documented native controls, usable keyboard/sheets, accessible targets and no overlapping native/web navigation. |
| Stop during rate-limit backoff | No subsequent retry request starts. |
| Provider reports token limit / stream disconnects | Transport is not accepted as complete; recovery or an actionable failure occurs. |
| Two-block patch cut off in block two | Neither block is committed. |

## Remaining limitations

Targeting is a bounded lexical heuristic, not full natural-language understanding. Preservation uses source extraction rather than AST or runtime proof. Provider quality and supported capabilities still determine generated results. Native appearance must be evaluated on an actual supported iOS host; better prompting cannot make HTML implement unavailable entitlements or backend services.
