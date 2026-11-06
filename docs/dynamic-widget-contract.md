# Dynamic widget contract (1.8.3)

Publish snapshot.timeRange:{startMs,endMs} using absolute Unix milliseconds and
snapshot.display: countdown | elapsed | remainingProgress | elapsedProgress.
End must be strictly after start; both values must be finite positive timestamps.
Optional upcomingLabel, inProgressLabel and completedLabel belong in timeRange.

This schema is generic and contains no shift/event/workout-specific logic.
Native Text(timerInterval:) and ProgressView(timerInterval:) handle ticking.
Circular Lock Screen widgets use system circular progress; Home Screen and
rectangular widgets use bars; inline widgets display timer text only.
Static progress remains appropriate for non-time metrics. A custom numeric
percent label or custom drawn ring is not claimed to update live.

The read-only provider generates current/start/end timeline entries. iOS owns
when entries appear; these are not exact background callbacks. No per-second
reloads, server polling or arbitrary JavaScript execution are needed for time.

Local dataBindings and remote JSON bindings support timeRange.startMs/endMs.
Publish changes/deletions explicitly. Old deadlineMs countdowns and fixed-value
widgets remain supported. Existing apps need an edit to publish their actual
start/end dates; arbitrary HTML cannot safely be migrated by guessing semantics.

WidgetTests covers bounds, round trips, bindings and timeline states. Those tests
need Xcode and were not executed here. Source/bridge/JS checks ran locally.
APNs is unnecessary for native timers. Live remote data still depends on system
refresh opportunities and must be presented with honest freshness information.

## Custom composition and time formats (1.8.5)

`capabilities.list().widgetCustomization` advertises schemaVersion 2, supported
node types/time formats, `liveSelectedTimeUnits` and size/depth limits.

Set snapshot.timeFormat to `automatic`, `hoursMinutesSeconds`, `minutesSeconds`,
`hoursMinutes`, `seconds`, `minutes` or `hours`. This also applies to deadlineMs.
On iOS 18+, selected units use Apple's native discrete date-offset formatting.
The output is localized (units/separators are chosen by iOS). Interval boundary
entries freeze custom formats at the initial/final value; their delivery remains
system-controlled. Standard clock timers remain natively bounded. On iOS 16/17,
seconds-only falls back to live MM:SS, and minute/hour-only formats use a rolling
120-entry minute timeline, requested for refresh after the normal interval. This
is not a guarantee of per-minute delivery. No second-by-second reloads are used.

`snapshot.content` replaces the template with an element tree.
`snapshot.familyContent` overrides that tree by family, including systemExtraLarge
on iPad. Missing family overrides use content, then the existing template. Use a
single short row for accessoryInline. Lock Screen colors/tints and available space
are controlled by iOS. This does not permit HTML, CSS, arbitrary Swift, JS loops
or unrestricted animation inside WidgetKit.

Elements:
- Containers: row, column, overlay; children is an array of elements. Compose grids
  from nested rows/columns, or layer rings, icons, labels and shapes in overlays.
- text: literal text or field:title/subtitle/value/unit/footer/eyebrow.
- timer: uses snapshot timeRange/display or deadlineMs; optional node timeFormat.
- progress/ring: native time-based display when timeRange is present, or static
  node.progress (0...1) / snapshot.progress. All timers use the snapshot interval.
- symbol: systemSymbol plus monochrome/hierarchical/palette/multicolor rendering;
  unknown symbols fall back to questionmark.circle.
- image: embedded imageBase64, falling back to the snapshot image; scaled to fit.
- circle, rectangle, capsule, spacer, divider.

Every element supports alignment (leading/center/trailing), row verticalAlignment
(top/center/bottom/firstTextBaseline), spacing/padding (0...40), fontSize (8...96),
fontWeight (regular/medium/semibold/bold/heavy), fontDesign
(default/rounded/serif/monospaced), lineLimit (1...6), minimumScale (0.3...1),
foregroundHex/backgroundHex/borderHex, borderWidth (0...12), cornerRadius (0...100),
opacity (0...1), width/height (1...600), expand (fill width), accessibilityLabel.
Container styles inherit, while explicit child styles override them. Limit fixed
sizes on accessories. Use family-specific trees and scale long timer text.

At most 96 nodes across all trees, six child levels, 120 KB serialized per tree,
100 KB per embedded node image. Invalid trees reject publication, rather than
silently rendering a different design. Existing fields/bindings remain supported.
Set automaticStatus:false to keep custom subtitle/footer/unit text. Whole-widget
navigation/actions still work. Use legacy item-list templates for multiple link
or action destinations; custom nodes do not add arbitrary executable actions.

Example (start/end supplied by the app's own data model):

```js
await HTMLAppNative.widgets.configure({
  id: 'session', name: 'Session', families: ['systemSmall', 'accessoryCircular'],
  snapshot: {
    timeRange: {startMs, endMs}, display: 'remainingProgress',
    timeFormat: 'hoursMinutes', automaticStatus: false,
    content: {type:'column', padding:14, spacing:8, children:[
      {type:'text', text:'Time remaining', fontSize:14},
      {type:'timer', fontSize:28, fontWeight:'bold', expand:true},
      {type:'progress'}
    ]},
    familyContent: {
      accessoryCircular: {type:'overlay', children:[
        {type:'ring'},
        {type:'column', padding:10, children:[
          {type:'symbol', systemSymbol:'clock', fontSize:13},
          {type:'timer', timeFormat:'minutesSeconds', fontSize:11, minimumScale:0.5}
        ]}
      ]}
    }
  }
});
```

Existing apps automatically receive the template alignment fix. They need a Forge
edit and republish to request new formats or layouts. Xcode/device checks still
need to cover each family on iOS 16/17/18/26, including long timers, large text,
accessibility, tinted rendering and interval boundaries.
