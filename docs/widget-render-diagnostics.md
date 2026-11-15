# Blank-widget device test

The shared receipt proves decoding only. These diagnostics deliberately distinguish:

- `timeline`: definition was resolved from the shared store.
- `completed`: timeline construction finished, before the provider calls completion.
- `submitted`: the Primary provider's completion call returned.
- `view`: the widget's SwiftUI body was evaluated.

None proves that WidgetKit successfully archived or displayed pixels. Receipts are per phase and family, so separate instances of the same family can still overwrite one another. Only receipts matching the current probe are shown. View construction receipts have no definition digest because the timeline may transform presentation fields for its entry date.

## Test without another code change

1. Publish Pretzel Plan once, leave the HTML app, and open Settings → Widgets & Background with Developer Mode enabled. Start Extension Read Test, return to Home/Lock Screen, then Read Diagnostic Result. Record the per-family rows and configured kind/family list.
2. Enable Plain-Text Widget Test. It preserves the widget definitions and temporarily displays `HTMLApp OK` through the Primary widget provider. View the same Home and Lock placements, then read diagnostics again.
3. Restore Normal Widget Content. The toggle persists across restarts until restored, and only affects Primary widget views, not Live Activities, Control Center, or the voice launcher.

If plain text displays but normal content does not, investigate content-dependent view construction, resource sizes and WidgetKit archiving. If both remain blank after timeline completion, inspect extension/renderer logs, installation and stale widget kinds. A missing completion receipt alone does not prove a crash: iOS may not have requested that family for the current probe.

Check device Analytics Data for matching HTMLAppWidgets crash or JetsamEvent records if available. Source checks and data receipts are not substitutes for this device test.

This patch also removes explicit value-animation wrappers around declarative nodes to reduce archive complexity. That is a compatibility experiment, not a confirmed explanation for blank Home widgets, which may use only built-in list templates.
