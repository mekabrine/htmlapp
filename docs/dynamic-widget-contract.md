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
