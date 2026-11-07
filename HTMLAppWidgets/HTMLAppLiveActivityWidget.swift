import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

@available(iOS 16.2, *)
struct HTMLAppLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HTMLAppLiveActivityAttributes.self) { context in
            region("lockScreen", context: context)
                .padding(14)
                .activityBackgroundTint(context.state.backgroundHex.map { Color(htmlAppHex: $0) } ?? Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(Color(htmlAppHex: context.state.accentHex))
                .widgetURL(activityURL(context.attributes))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { region("expandedLeading", context: context) }
                DynamicIslandExpandedRegion(.center) { region("expandedCenter", context: context) }
                DynamicIslandExpandedRegion(.trailing) { region("expandedTrailing", context: context) }
                DynamicIslandExpandedRegion(.bottom) { region("expandedBottom", context: context) }
            } compactLeading: {
                region("compactLeading", context: context)
            } compactTrailing: {
                region("compactTrailing", context: context)
            } minimal: {
                region("minimal", context: context)
            }
            .widgetURL(activityURL(context.attributes))
        }
    }

    @ViewBuilder private func region(_ name: String, context: ActivityViewContext<HTMLAppLiveActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let node = context.state.presentation?[name], let snapshot = snapshot(context) {
                HTMLAppWidgetElementView(node: node, snapshot: snapshot, date: Date())
            } else { fallback(name, context: context) }
            if name == "lockScreen" || name == "expandedBottom" {
                HStack {
                    ForEach(context.state.actions ?? []) { action in
                        if action.kind == "end" {
                            if #available(iOS 17.0, *) {
                                Button(intent: HTMLAppEndLiveActivityIntent(appID: context.attributes.appID, activityID: context.attributes.activityID)) {
                                    Text(action.title)
                                }.buttonStyle(.bordered)
                            } else if let url = activityURL(context.attributes) {
                                Link("Open to " + action.title, destination: url)
                            }
                        } else if let url = activityURL(context.attributes) {
                            Link(action.title, destination: url)
                        }
                    }
                }.font(.caption)
            }
        }
    }

    @ViewBuilder private func fallback(_ name: String, context: ActivityViewContext<HTMLAppLiveActivityAttributes>) -> some View {
        switch name {
        case "minimal", "compactLeading", "expandedLeading":
            Image(systemName: context.attributes.systemSymbol).foregroundStyle(Color(htmlAppHex: context.state.accentHex))
        case "compactTrailing", "expandedTrailing":
            metric(context.state).font(.caption.monospacedDigit()).lineLimit(1)
        case "expandedCenter":
            Text(context.attributes.title).font(.headline).lineLimit(1)
        default:
            VStack(alignment: .leading, spacing: 8) {
                if name == "lockScreen" {
                    HStack {
                        Image(systemName: context.attributes.systemSymbol)
                        Text(context.attributes.title).font(.headline).lineLimit(1)
                        Spacer(minLength: 0)
                        metric(context.state).font(.headline.monospacedDigit())
                    }
                }
                Text(context.state.subtitle).font(.subheadline).lineLimit(2)
                if let value = context.state.secondaryValue, !value.isEmpty {
                    HStack {
                        Text(context.state.secondaryLabel ?? "Details").foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if let deadline = context.state.secondaryDeadline {
                            Text(timerInterval: Date()...max(Date(), deadline), countsDown: true)
                        } else { Text(value) }
                    }.font(.caption)
                }
                if let range = context.state.timeRange?.interval {
                    ProgressView(timerInterval: range, countsDown: context.state.display != "elapsedProgress")
                } else if let progress = context.state.progress {
                    ProgressView(value: progress).tint(Color(htmlAppHex: context.state.accentHex))
                }
                if context.isStale { Text("Last update may be outdated").font(.caption2) }
                if let footer = context.state.footer { Text(footer).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
            }
        }
    }
    @ViewBuilder private func metric(_ state: HTMLAppLiveActivityAttributes.ContentState) -> some View {
        if let deadline = state.primaryDeadline {
            Text(timerInterval: Date()...max(Date(), deadline), countsDown: true)
        } else { Text(state.compactLabel ?? state.value) }
    }
    private func snapshot(_ context: ActivityViewContext<HTMLAppLiveActivityAttributes>) -> HTMLAppWidgetSnapshot? {
        var data: [String: Any] = ["title": context.attributes.title, "subtitle": context.state.subtitle,
            "value": context.state.value, "systemSymbol": context.attributes.systemSymbol,
            "accentHex": context.state.accentHex, "automaticStatus": false]
        data["footer"] = context.state.footer
        data["progress"] = context.state.progress
        data["deadlineMs"] = context.state.primaryDeadline.map { $0.timeIntervalSince1970 * 1000 }
        data["display"] = context.state.display
        data["timeFormat"] = context.state.timeFormat
        if let range = context.state.timeRange { data["timeRange"] = ["startMs": range.startMs, "endMs": range.endMs] }
        guard let bytes = try? JSONSerialization.data(withJSONObject: data) else { return nil }
        return try? JSONDecoder().decode(HTMLAppWidgetSnapshot.self, from: bytes)
    }
    private func activityURL(_ attributes: HTMLAppLiveActivityAttributes) -> URL? {
        var parts = URLComponents()
        parts.scheme = "htmlapp"; parts.host = "open"
        parts.queryItems = [URLQueryItem(name: "id", value: attributes.appID)]
        return parts.url
    }
}
