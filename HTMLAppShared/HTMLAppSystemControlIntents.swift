import AppIntents
import ActivityKit
import Foundation
import UserNotifications

@available(iOS 18.0, *)
struct HTMLAppSystemControlEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "HTMLApp Control"
    static var defaultQuery = HTMLAppSystemControlQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ definition: HTMLAppSystemControl) {
        id = definition.id
        name = definition.appName + " · " + definition.title
    }

    init(id: String, name: String) { self.id = id; self.name = name }
}

@available(iOS 18.0, *)
struct HTMLAppSystemControlQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HTMLAppSystemControlEntity] {
        let definitions = try HTMLAppSystemControlStore.controls()
        return identifiers.map { id in
            definitions.first(where: { $0.id == id }).map(HTMLAppSystemControlEntity.init) ??
                HTMLAppSystemControlEntity(id: id, name: "Unavailable — open HTMLApp")
        }
    }
    func suggestedEntities() async throws -> [HTMLAppSystemControlEntity] {
        try HTMLAppSystemControlStore.controls().map(HTMLAppSystemControlEntity.init)
    }
}

@available(iOS 18.0, *)
struct HTMLAppButtonOptions: DynamicOptionsProvider {
    func results() async throws -> [HTMLAppSystemControlEntity] {
        try HTMLAppSystemControlStore.controls().filter { $0.type == "button" && $0.action?.kind != "open" }.map(HTMLAppSystemControlEntity.init)
    }
}

@available(iOS 18.0, *)
struct HTMLAppOpenOptions: DynamicOptionsProvider {
    func results() async throws -> [HTMLAppSystemControlEntity] {
        try HTMLAppSystemControlStore.controls().filter { $0.type == "button" && $0.action?.kind == "open" }.map(HTMLAppSystemControlEntity.init)
    }
}

@available(iOS 18.0, *)
struct HTMLAppToggleOptions: DynamicOptionsProvider {
    func results() async throws -> [HTMLAppSystemControlEntity] {
        try HTMLAppSystemControlStore.controls().filter { $0.type == "toggle" }.map(HTMLAppSystemControlEntity.init)
    }
}

@available(iOS 18.0, *)
struct HTMLAppButtonConfiguration: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Choose an HTMLApp button"
    @Parameter(title: "Project / Button", optionsProvider: HTMLAppButtonOptions())
    var control: HTMLAppSystemControlEntity?
}

@available(iOS 18.0, *)
struct HTMLAppToggleConfiguration: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Choose an HTMLApp toggle"
    @Parameter(title: "Project / Toggle", optionsProvider: HTMLAppToggleOptions())
    var control: HTMLAppSystemControlEntity?
}

@available(iOS 18.0, *)
struct HTMLAppOpenConfiguration: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Choose an HTMLApp to open"
    @Parameter(title: "Project / Destination", optionsProvider: HTMLAppOpenOptions())
    var control: HTMLAppSystemControlEntity?
}

@available(iOS 18.0, *)
struct HTMLAppOpenSystemControlIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open HTMLApp project"
    static var openAppWhenRun = true
    @Parameter(title: "Control") var target: HTMLAppSystemControlEntity
    init() {}
    init(control: HTMLAppSystemControlEntity) { target = control }

    func perform() async throws -> some IntentResult {
        try HTMLAppSystemControlStore.repository().mutate { document in
            guard let definition = document.controls.first(where: { $0.id == target.id }),
                  definition.type == "button", definition.action?.kind == "open" else { throw HTMLAppSystemControlError.missing }
            document.pendingOpen = HTMLAppSystemControlOpen(appID: definition.appID,
                controlID: definition.controlID, route: definition.action?.route)
        }
        await MainActor.run {
            NotificationCenter.default.post(name: HTMLAppSystemControlStore.openRequested, object: nil)
        }
        return .result()
    }
}

@available(iOS 18.0, *)
struct HTMLAppRunSystemControlIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Run HTMLApp control"
    static var openAppWhenRun = false
    @Parameter(title: "Control") var controlID: String
    init() {}
    init(controlID: String) { self.controlID = controlID }
    func perform() async throws -> some IntentResult {
        try await HTMLAppSystemControlExecutor.shared.perform(controlID: controlID)
        return .result()
    }
}

@available(iOS 18.0, *)
struct HTMLAppSetSystemControlIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Set HTMLApp toggle"
    static var openAppWhenRun = false
    @Parameter(title: "Control") var controlID: String
    @Parameter(title: "Enabled") var value: Bool
    init() {}
    init(controlID: String) { self.controlID = controlID }
    func perform() async throws -> some IntentResult {
        let appID = try HTMLAppSystemControlStore.repository().mutate { document in
            guard let definition = document.controls.first(where: { $0.id == controlID }),
                  definition.type == "toggle", let key = definition.stateKey else { throw HTMLAppSystemControlError.missing }
            document.values[definition.appID, default: [:]][key] = .boolean(value)
            return definition.appID
        }
        HTMLAppSystemControlStore.reload()
        await MainActor.run { NotificationCenter.default.post(name: HTMLAppSystemControlStore.stateChanged, object: appID) }
        return .result()
    }
}

/// All background actions have one native implementation. LiveActivityIntent
/// ensures execution in the host app, including access to its consent choices.
@available(iOS 16.2, *)
actor HTMLAppSystemControlExecutor {
    static let shared = HTMLAppSystemControlExecutor()

    func perform(controlID: String) async throws {
        let document = try HTMLAppSystemControlStore.repository().read()
        guard let control = document.controls.first(where: { $0.id == controlID }),
              control.isValid, let action = control.action else { throw HTMLAppSystemControlError.missing }
        switch action.kind {
        case "set", "increment", "event":
            try HTMLAppSystemControlStore.repository().mutate { current in
                guard current.controls.contains(control) else { throw HTMLAppSystemControlError.missing }
                switch action.kind {
                case "set":
                    guard let key = action.key, let value = action.value else { throw HTMLAppSystemControlError.invalid }
                    current.values[control.appID, default: [:]][key] = value
                case "increment":
                    guard let key = action.key, let step = action.step else { throw HTMLAppSystemControlError.invalid }
                    let old: Double
                    if let value = current.values[control.appID]?[key] {
                        guard case .number(let number) = value else { throw HTMLAppSystemControlError.invalid }
                        old = number
                    } else { old = 0 }
                    let updated = old + step
                    guard updated.isFinite, abs(updated) <= 1_000_000_000 else { throw HTMLAppSystemControlError.limit }
                    current.values[control.appID, default: [:]][key] = .number(updated)
                default:
                    try HTMLAppSystemControlStore.append(.init(appID: control.appID, controlID: control.controlID,
                        action: "event", key: action.key, value: action.value), to: &current)
                }
                try HTMLAppSystemControlStore.validateValues(appID: control.appID, in: current)
            }
        case "activity.start", "activity.update":
            try requirePermission("liveActivities", appID: control.appID)
            guard let data = control.activity,
                  let template = try? JSONDecoder().decode(HTMLAppControlActivityTemplate.self, from: data),
                  ActivityAuthorizationInfo().areActivitiesEnabled else { throw HTMLAppSystemControlError.unavailable }
            let activities = Activity<HTMLAppLiveActivityAttributes>.activities.filter { $0.attributes.appID == control.appID }
            let existing = activities.first { $0.attributes.activityID == action.activityID }
            if action.kind == "activity.update" || existing == nil {
                var state = template.state
                if let duration = template.durationSeconds {
                    let now = Date()
                    state.primaryDeadline = now.addingTimeInterval(duration)
                    state.timeRange = HTMLAppWidgetTimeRange(startMs: now.timeIntervalSince1970 * 1000,
                        endMs: now.addingTimeInterval(duration).timeIntervalSince1970 * 1000)
                }
                if action.kind == "activity.update" {
                    guard let existing else { throw HTMLAppSystemControlError.missing }
                    try Self.validate(state: state, attributes: existing.attributes)
                    await existing.update(ActivityContent(state: state, staleDate: state.staleDate))
                } else {
                    guard activities.count < 3 else { throw HTMLAppSystemControlError.limit }
                    try Self.validate(state: state, attributes: template.attributes)
                    _ = try Activity.request(attributes: template.attributes,
                        content: ActivityContent(state: state, staleDate: state.staleDate), pushType: nil)
                }
            }
        case "activity.pause", "activity.resume", "activity.end", "activity.complete":
            try requirePermission("liveActivities", appID: control.appID)
            try await activityAction(appID: control.appID, activityID: action.activityID ?? "", kind: action.kind)
        case "notification.schedule", "notification.cancel":
            try requirePermission("notifications", appID: control.appID)
            guard let notification = action.notification else { throw HTMLAppSystemControlError.invalid }
            let center = UNUserNotificationCenter.current()
            let identifier = "htmlapp.control." + control.appID + "." + notification.id
            if action.kind == "notification.cancel" {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
            } else {
                guard let title = notification.title, let body = notification.body,
                      let delay = notification.delaySeconds else { throw HTMLAppSystemControlError.invalid }
                let settings = await center.notificationSettings()
                guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { throw HTMLAppSystemControlError.permission }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                let request = UNNotificationRequest(identifier: identifier, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))
                try await center.add(request)
            }
        default: throw HTMLAppSystemControlError.invalid
        }
        HTMLAppSystemControlStore.reload()
        await MainActor.run {
            NotificationCenter.default.post(name: HTMLAppSystemControlStore.stateChanged, object: control.appID)
        }
    }

    private func requirePermission(_ name: String, appID: String) throws {
        guard Bundle.main.bundleURL.pathExtension != "appex",
              UserDefaults.standard.string(forKey: "htmlPermission.\(appID).\(name)") == "allow" else {
            throw HTMLAppSystemControlError.permission
        }
    }

    func activityAction(appID: String, activityID: String, kind: String) async throws {
        try requirePermission("liveActivities", appID: appID)
        guard let activity = Activity<HTMLAppLiveActivityAttributes>.activities.first(where: {
            $0.attributes.appID == appID && $0.attributes.activityID == activityID
        }) else { throw HTMLAppSystemControlError.missing }
        var state = activity.content.state
        defer {
            Task { @MainActor in
                NotificationCenter.default.post(name: HTMLAppSystemControlStore.stateChanged, object: appID)
            }
        }
        let now = Date()
        switch kind {
        case "activity.end":
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            return
        case "activity.complete":
            state.primaryDeadline = nil
            state.secondaryDeadline = nil
            state.timeRange = nil
            state.pausedRemaining = nil
            state.pausedElapsed = nil
            state.value = "Complete"
            state.compactLabel = "Done"
            state.progress = 1
            state.actions = state.actions?.filter { $0.kind == "open" }
            try Self.validate(state: state, attributes: activity.attributes)
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .default)
            return
        case "activity.pause":
            if state.pausedRemaining != nil { return }
            guard let end = state.timeRange?.interval?.upperBound ?? state.primaryDeadline else { throw HTMLAppSystemControlError.invalid }
            guard end > now else { throw HTMLAppSystemControlError.invalid }
            state.pausedRemaining = end.timeIntervalSince(now)
            state.pausedElapsed = state.timeRange?.interval.map { max(0, now.timeIntervalSince($0.lowerBound)) }
            state.primaryDeadline = nil
            state.timeRange = nil
        case "activity.resume":
            guard let remaining = state.pausedRemaining else { return }
            let end = now.addingTimeInterval(remaining)
            state.primaryDeadline = end
            if let elapsed = state.pausedElapsed {
                state.timeRange = HTMLAppWidgetTimeRange(startMs: now.addingTimeInterval(-elapsed).timeIntervalSince1970 * 1000,
                    endMs: end.timeIntervalSince1970 * 1000)
            }
            state.pausedRemaining = nil
            state.pausedElapsed = nil
        default: throw HTMLAppSystemControlError.invalid
        }
        state.staleDate = nil
        try Self.validate(state: state, attributes: activity.attributes)
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    static func validate(state: HTMLAppLiveActivityAttributes.ContentState, attributes: HTMLAppLiveActivityAttributes) throws {
        let encoder = JSONEncoder()
        guard try encoder.encode(state).count + encoder.encode(attributes).count <= 3800 else { throw HTMLAppSystemControlError.limit }
    }
}

@available(iOS 17.0, *)
struct HTMLAppRunLiveActivityActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Update HTMLApp activity"
    static var openAppWhenRun = false
    @Parameter(title: "App") var appID: String
    @Parameter(title: "Activity") var activityID: String
    @Parameter(title: "Action") var actionID: String
    init() {}
    init(appID: String, activityID: String, actionID: String) {
        self.appID = appID; self.activityID = activityID; self.actionID = actionID
    }
    func perform() async throws -> some IntentResult {
        guard let activity = Activity<HTMLAppLiveActivityAttributes>.activities.first(where: {
            $0.attributes.appID == appID && $0.attributes.activityID == activityID
        }), let action = activity.content.state.actions?.first(where: { $0.id == actionID }),
              ["pause", "resume", "complete"].contains(action.kind) else { throw HTMLAppSystemControlError.missing }
        try await HTMLAppSystemControlExecutor.shared.activityAction(appID: appID, activityID: activityID, kind: "activity." + action.kind)
        return .result()
    }
}
