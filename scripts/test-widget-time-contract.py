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
assert 'Text(timerInterval: range, countsDown: snapshot.countsDown, showsHours:' in widget
assert 'range.lowerBound, range.upperBound' in widget
assert 'snapshot.presentation(at: date)' in widget
assert 'snapshot.nativeTimeInterval != nil || snapshot.countdownDeadline != nil' in widget
assert 'ForgeWidgetTimeContract.issues' in read('HTMLAppV3/AIGenerationView.swift')
assert 'ForgeWidgetTimeContract.issues' in read('HTMLAppV3/AIGenerationService.swift')
print('PASS: dynamic widget transport, rendering, timeline and Forge acceptance wiring')

assert 'struct HTMLAppWidgetElement: Codable, Hashable' in shared
assert 'count <= 96' in shared and 'depth <= 6' in shared
assert 'snapshot.customContent(for: family.storageName)' in widget
assert 'familyContent: familyContent' in bridge
assert 'node.isValid(count: &count)' in bridge
assert 'HTMLAppWidgetSnapshot.timeFormats.contains(timeFormat)' in bridge
assert 'if #available(iOS 18.0, *)' in widget and 'allowedFields: fields' in widget
assert '.multilineTextAlignment(.center)' in widget and '.padding(.horizontal, 10)' in widget
assert 'maxElements' in bridge and 'liveSelectedTimeUnits' in bridge
assert 'CUSTOM WIDGET DESIGN (schemaVersion 2)' in read('HTMLAppV3/ForgeBackendContract.swift')
print('PASS: custom widget validation, transport, native formatting and family renderer wiring')
