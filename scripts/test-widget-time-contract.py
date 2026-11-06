from pathlib import Path
root = Path(__file__).resolve().parents[1]
read = lambda path: (root/path).read_text()
shared = read('HTMLAppShared/HTMLAppWidgetShared.swift')
bridge = read('HTMLAppV3/NativeAPIBridge.swift')
widget = read('HTMLAppWidgets/HTMLAppWidgets.swift')
assert 'struct HTMLAppWidgetTimeRange: Codable, Hashable' in shared
assert 'endMs > startMs' in shared
assert 'timeRange: timeRange,' in bridge and 'display: display,' in bridge
assert 'HTMLAppWidgetSnapshot.timeDisplays.contains(display)' in bridge
assert '"timeRange.startMs", "timeRange.endMs"' in shared
assert 'ProgressView(timerInterval: range, countsDown: snapshot.countsDown)' in widget
assert 'Text(timerInterval: range, countsDown: snapshot.countsDown)' in widget
assert 'range.lowerBound, range.upperBound' in widget
assert 'snapshot.presentation(at: date)' in widget
assert 'snapshot.nativeTimeInterval != nil || snapshot.countdownDeadline != nil' in widget
assert 'ForgeWidgetTimeContract.issues' in read('HTMLAppV3/AIGenerationView.swift')
assert 'ForgeWidgetTimeContract.issues' in read('HTMLAppV3/AIGenerationService.swift')
print('PASS: dynamic widget transport, rendering, timeline and Forge acceptance wiring')
