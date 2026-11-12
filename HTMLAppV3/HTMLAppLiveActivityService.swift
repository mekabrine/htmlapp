import Foundation
import ActivityKit
import UIKit

@available(iOS 16.2, *)
enum HTMLAppLiveActivityService {
    enum Failure: LocalizedError {
        case unavailable, badArguments, limit, notFound
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Live Activities are disabled or not available on this iOS device."
            case .badArguments: return "Invalid Live Activity: check id/title, layout, finite time values and the 3.8 KB combined payload budget."
            case .limit: return "This HTML app can run up to three Live Activities at once."
            case .notFound: return "No active Live Activity with that id belongs to this HTML app."
            }
        }
    }

    private static func clip(_ any: Any?, max: Int) -> String {
        String(((any as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(max))
    }

    private static func validID(_ any: Any?) -> String? {
        let raw = clip(any, max: 65)
        guard !raw.isEmpty, raw.count <= 64,
              raw.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { return nil }
        return raw
    }

    private static func symbol(_ value: Any?) -> String {
        let requested = clip(value, max: 48)
        return UIImage(systemName: requested) == nil ? "app.fill" : requested
    }

    private static func content(_ args: [String: Any],
                                previous: HTMLAppLiveActivityAttributes.ContentState? = nil
    ) throws -> HTMLAppLiveActivityAttributes.ContentState {
        let hex = clip(args["accentHex"], max: 7)
        let goodHex = hex.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil
        let value = args["progress"] as? NSNumber
        let primary = args["primaryDeadlineMs"] as? NSNumber
        let secondary = args["secondaryDeadlineMs"] as? NSNumber
        var actions = previous?.actions
        if let raw = args["actions"] {
            if raw is NSNull { actions = nil }
            else {
                guard JSONSerialization.isValidJSONObject(raw), let bytes = try? JSONSerialization.data(withJSONObject: raw),
                      let decoded = try? JSONDecoder().decode([HTMLAppLiveActivityAction].self, from: bytes),
                      decoded.count <= 3, Set(decoded.map(\.id)).count == decoded.count,
                      decoded.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 40 && !$0.title.isEmpty && $0.title.count <= 30 && ["open", "end", "pause", "resume", "complete"].contains($0.kind) }) else { throw Failure.badArguments }
                actions = decoded
            }
        }
        var presentation = previous?.presentation
        if let raw = args["presentation"] {
            if raw is NSNull { presentation = nil }
            else {
                guard JSONSerialization.isValidJSONObject(raw),
                      let bytes = try? JSONSerialization.data(withJSONObject: raw), bytes.count < 3500,
                      let decoded = try? JSONDecoder().decode([String: HTMLAppWidgetElement].self, from: bytes),
                      Set(decoded.keys).isSubset(of: Set(["lockScreen", "compactLeading", "compactTrailing", "minimal", "expandedLeading", "expandedCenter", "expandedTrailing", "expandedBottom"])) else { throw Failure.badArguments }
                var count = 0
                guard decoded.values.allSatisfy({ $0.isValid(count: &count) }), count <= 48 else { throw Failure.badArguments }
                presentation = decoded
            }
        }
        var range = previous?.timeRange
        if let raw = args["timeRange"] {
            if raw is NSNull { range = nil }
            else {
                guard let object = raw as? [String: Any], let start = object["startMs"] as? Double,
                      let end = object["endMs"] as? Double,
                      HTMLAppWidgetSnapshot.validDeadline(start) != nil,
                      HTMLAppWidgetSnapshot.validDeadline(end) != nil, start < end else { throw Failure.badArguments }
                range = HTMLAppWidgetTimeRange(startMs: start, endMs: end)
            }
        }
        let staleMs = (args["staleDateMs"] as? NSNumber)?.doubleValue
        if let staleMs, HTMLAppWidgetSnapshot.validDeadline(staleMs) == nil { throw Failure.badArguments }
        if let value, !value.doubleValue.isFinite { throw Failure.badArguments }
        for deadline in [primary, secondary].compactMap({ $0 }) {
            guard HTMLAppWidgetSnapshot.validDeadline(deadline.doubleValue) != nil else { throw Failure.badArguments }
        }
        let display = args["display"] as? String ?? previous?.display
        let format = args["timeFormat"] as? String ?? previous?.timeFormat
        guard display == nil || HTMLAppWidgetSnapshot.timeDisplays.contains(display!),
              format == nil || HTMLAppWidgetSnapshot.timeFormats.contains(format!) else { throw Failure.badArguments }
        return .init(
            primaryDeadline: primary.map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } ?? previous?.primaryDeadline,
            secondaryDeadline: secondary.map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } ?? previous?.secondaryDeadline,
            subtitle: args["subtitle"] == nil ? (previous?.subtitle ?? "") : clip(args["subtitle"], max: 120),
            value: args["value"] == nil ? (previous?.value ?? "") : clip(args["value"], max: 24),
            progress: value.map { max(0, min(1, $0.doubleValue)) } ?? previous?.progress,
            accentHex: goodHex ? hex : (previous?.accentHex ?? "#3576D3"),
            secondaryLabel: args["secondaryLabel"] == nil ? previous?.secondaryLabel : clip(args["secondaryLabel"], max: 36),
            secondaryValue: args["secondaryValue"] == nil ? previous?.secondaryValue : clip(args["secondaryValue"], max: 28),
            footer: args["footer"] == nil ? previous?.footer : clip(args["footer"], max: 90),
            backgroundHex: {
                let candidate = clip(args["backgroundHex"], max: 7)
                return candidate.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil
                    ? candidate : previous?.backgroundHex
            }(),
            compactLabel: args["compactLabel"] == nil ? previous?.compactLabel
                : clip(args["compactLabel"], max: 10),
            actions: actions, presentation: presentation,
            staleDate: args["staleDateMs"] is NSNull ? nil : staleMs.map { Date(timeIntervalSince1970: $0 / 1000) } ?? previous?.staleDate,
            timeRange: range, display: display, timeFormat: format,
            pausedRemaining: args["timeRange"] != nil || args["primaryDeadlineMs"] != nil ? nil : previous?.pausedRemaining,
            pausedElapsed: args["timeRange"] != nil || args["primaryDeadlineMs"] != nil ? nil : previous?.pausedElapsed
        )
    }

    static func controlTemplate(appID: String, args: [String: Any]) throws -> Data {
        guard let id = validID(args["id"]), !clip(args["title"], max: 75).isEmpty else { throw Failure.badArguments }
        let attributes = HTMLAppLiveActivityAttributes(appID: appID, activityID: id,
            title: clip(args["title"], max: 75), systemSymbol: symbol(args["systemSymbol"]))
        let state = try content(args)
        try validatePayload(attributes: attributes, state: state)
        let duration = (args["durationSeconds"] as? NSNumber)?.doubleValue
        if let duration, !duration.isFinite || !(1...28_800).contains(duration) { throw Failure.badArguments }
        return try JSONEncoder().encode(HTMLAppControlActivityTemplate(attributes: attributes, state: state, durationSeconds: duration))
    }

    private static func matching(appID: String, id: String) -> Activity<HTMLAppLiveActivityAttributes>? {
        Activity<HTMLAppLiveActivityAttributes>.activities.first {
            $0.attributes.appID == appID && $0.attributes.activityID == id
        }
    }

    static func list(appID: String) -> [[String: Any]] {
        Activity<HTMLAppLiveActivityAttributes>.activities
            .filter { $0.attributes.appID == appID }
            .map {
                ["id": $0.attributes.activityID, "title": $0.attributes.title,
                 "systemSymbol": $0.attributes.systemSymbol,
                 "subtitle": $0.content.state.subtitle,
                 "value": $0.content.state.value,
                 "secondaryLabel": $0.content.state.secondaryLabel ?? "",
                 "secondaryValue": $0.content.state.secondaryValue ?? "",
                 "footer": $0.content.state.footer ?? "",
                 "backgroundHex": $0.content.state.backgroundHex ?? "",
                 "compactLabel": $0.content.state.compactLabel ?? "",
                 "isPaused": $0.content.state.pausedRemaining != nil,
                 "pausedRemainingSeconds": $0.content.state.pausedRemaining ?? 0,
                 "state": String(describing: $0.activityState)]
            }
    }

    static func start(appID: String, args: [String: Any]) throws -> [String: Any] {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw Failure.unavailable }
        guard let id = validID(args["id"]),
              !clip(args["title"], max: 75).isEmpty else { throw Failure.badArguments }
        if let existing = matching(appID: appID, id: id) {
            return ["id": id, "activityID": existing.id, "alreadyActive": true]
        }
        guard list(appID: appID).count < 3 else { throw Failure.limit }
        let attrs = HTMLAppLiveActivityAttributes(
            appID: appID, activityID: id,
            title: clip(args["title"], max: 75),
            systemSymbol: symbol(args["systemSymbol"])
        )
        let state = try content(args)
        try validatePayload(attributes: attrs, state: state)
        let activity = try Activity.request(
            attributes: attrs,
            content: ActivityContent(state: state, staleDate: state.staleDate),
            pushType: nil
        )
        return ["id": id, "activityID": activity.id, "started": true]
    }

    static func update(appID: String, args: [String: Any]) async throws -> [String: Any] {
        guard let id = validID(args["id"]) else { throw Failure.badArguments }
        guard let activity = matching(appID: appID, id: id) else { throw Failure.notFound }
        let state = try content(args, previous: activity.content.state)
        try validatePayload(attributes: activity.attributes, state: state)
        await activity.update(ActivityContent(state: state, staleDate: state.staleDate))
        return ["id": id, "updated": true]
    }

    private static func validatePayload(attributes: HTMLAppLiveActivityAttributes,
                                        state: HTMLAppLiveActivityAttributes.ContentState) throws {
        let encoder = JSONEncoder()
        // Leave headroom below ActivityKit's combined 4 KB ceiling.
        guard try encoder.encode(attributes).count + encoder.encode(state).count <= 3800 else { throw Failure.badArguments }
    }

    static func end(appID: String, args: [String: Any]) async throws -> [String: Any] {
        guard let id = validID(args["id"]) else { throw Failure.badArguments }
        guard let activity = matching(appID: appID, id: id) else { throw Failure.notFound }
        await activity.end(ActivityContent(state: activity.content.state, staleDate: nil),
                           dismissalPolicy: .immediate)
        return ["id": id, "ended": true]
    }
}
