import Foundation
import WidgetKit

/// A small, serializable action vocabulary shared by the app and extensions.
/// Each value belongs to one saved HTMLApp; no JavaScript runs in an intent.
enum HTMLAppControlValue: Codable, Hashable {
    case boolean(Bool)
    case number(Double)
    case text(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let flag = try? value.decode(Bool.self) { self = .boolean(flag) }
        else if let number = try? value.decode(Double.self), number.isFinite, abs(number) <= 1_000_000_000 {
            self = .number(number)
        } else if let text = try? value.decode(String.self), text.count <= 240 { self = .text(text) }
        else { throw DecodingError.dataCorruptedError(in: value, debugDescription: "Expected a bounded scalar value.") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .boolean(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        }
    }

    var object: Any {
        switch self {
        case .boolean(let value): return value
        case .number(let value): return value
        case .text(let value): return value
        }
    }
}

struct HTMLAppSystemControlAction: Codable, Hashable {
    var kind: String
    var key: String? = nil
    var value: HTMLAppControlValue? = nil
    var step: Double? = nil
    var route: String? = nil
    var activityID: String? = nil
    var notification: HTMLAppControlNotification? = nil

    static let kinds: Set<String> = ["open", "set", "increment", "event", "activity.start", "activity.update", "activity.pause", "activity.resume", "activity.end", "activity.complete", "notification.schedule", "notification.cancel"]

    var isValid: Bool {
        guard Self.kinds.contains(kind), (route?.count ?? 0) <= 100,
              key == nil || HTMLAppSystemControl.validID(key) else { return false }
        switch kind {
        case "set": return HTMLAppSystemControl.validID(key) && value != nil
        case "increment":
            return HTMLAppSystemControl.validID(key) && step.map { $0.isFinite && abs($0) <= 1_000_000 } == true
        case "activity.start", "activity.update", "activity.pause", "activity.resume", "activity.end", "activity.complete":
            return HTMLAppSystemControl.validID(activityID)
        case "notification.schedule": return notification?.isValid == true
        case "notification.cancel": return HTMLAppSystemControl.validID(notification?.id)
        default: return true
        }
    }
}

struct HTMLAppControlNotification: Codable, Hashable {
    var id: String
    var title: String? = nil
    var body: String? = nil
    var delaySeconds: Double? = nil
    var isValid: Bool {
        guard let title, let body, let delaySeconds else { return false }
        return HTMLAppSystemControl.validID(id) && !title.isEmpty && title.count <= 100 && body.count <= 300 &&
            delaySeconds.isFinite && (1...604_800).contains(delaySeconds)
    }
}

struct HTMLAppSystemControl: Codable, Hashable, Identifiable {
    var appID: String
    var appName: String
    var controlID: String
    var title: String
    var systemSymbol: String
    var type: String
    var stateKey: String? = nil
    var action: HTMLAppSystemControlAction? = nil
    var activity: Data? = nil
    var id: String { appID + "::" + controlID }

    static func validID(_ value: String?) -> Bool {
        guard let value, (1...64).contains(value.count) else { return false }
        return value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil
    }

    var isValid: Bool {
        guard !appID.isEmpty, Self.validID(controlID), !title.isEmpty, title.count <= 60,
              appName.count <= 100, !systemSymbol.isEmpty, systemSymbol.count <= 80 else { return false }
        if type == "toggle" { return Self.validID(stateKey) && action == nil && activity == nil }
        guard type == "button", let action, action.isValid else { return false }
        if ["activity.start", "activity.update"].contains(action.kind) {
            guard #available(iOS 16.2, *), let activity,
                  let template = try? JSONDecoder().decode(HTMLAppControlActivityTemplate.self, from: activity) else { return false }
            return template.attributes.appID == appID && template.attributes.activityID == action.activityID
        }
        return activity == nil
    }

}

/// Validated by the host's Live Activity payload parser before publication.
@available(iOS 16.2, *)
struct HTMLAppControlActivityTemplate: Codable {
    var attributes: HTMLAppLiveActivityAttributes
    var state: HTMLAppLiveActivityAttributes.ContentState
    var durationSeconds: Double? = nil
}

struct HTMLAppSystemControlEvent: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var appID: String
    var controlID: String
    var action: String
    var date: Date = Date()
    var key: String? = nil
    var value: HTMLAppControlValue? = nil
}

struct HTMLAppSystemControlOpen: Codable {
    var appID: String
    var controlID: String
    var route: String?
    var createdAt: Date = Date()
}

struct HTMLAppSystemControlDocument: Codable {
    var controls: [HTMLAppSystemControl] = []
    var values: [String: [String: HTMLAppControlValue]] = [:]
    var events: [HTMLAppSystemControlEvent] = []
    var pendingOpen: HTMLAppSystemControlOpen? = nil
}

/// File coordination protects read/modify/write operations across intent and
/// app processes, including simultaneous toggles for different saved projects.
final class HTMLAppSystemControlRepository {
    let file: URL
    init(directory: URL) { file = directory.appendingPathComponent("htmlapp-system-controls-v1.json") }

    private func coordinated<Value>(write: Bool, _ body: (URL) throws -> Value) throws -> Value {
        var error: NSError?
        var result: Result<Value, Error>?
        let accessor: (URL) -> Void = { url in result = Result { try body(url) } }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        if write { coordinator.coordinate(writingItemAt: file, options: [], error: &error, byAccessor: accessor) }
        else { coordinator.coordinate(readingItemAt: file, options: [], error: &error, byAccessor: accessor) }
        if let error { throw HTMLAppWidgetRepository.failure("control_coordination_failed", error) }
        guard let result else { throw HTMLAppSystemControlError.storage }
        return try result.get()
    }

    private func read(_ url: URL) throws -> HTMLAppSystemControlDocument {
        do {
            let bytes = try Data(contentsOf: url)
            guard bytes.count <= 2_000_000 else { throw HTMLAppSystemControlError.storage }
            return try JSONDecoder().decode(HTMLAppSystemControlDocument.self, from: bytes)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return HTMLAppSystemControlDocument()
        }
    }

    func read() throws -> HTMLAppSystemControlDocument { try coordinated(write: false, read) }

    @discardableResult
    func mutate<Value>(_ operation: (inout HTMLAppSystemControlDocument) throws -> Value) throws -> Value {
        try coordinated(write: true) { url in
            var document = try read(url)
            let result = try operation(&document)
            let data = try JSONEncoder().encode(document)
            guard data.count <= 2_000_000 else { throw HTMLAppSystemControlError.limit }
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return result
        }
    }
}

enum HTMLAppSystemControlError: LocalizedError {
    case storage, invalid, missing, limit, permission, unavailable
    var errorDescription: String? {
        switch self {
        case .storage: return "Shared control data could not be read or saved. Unlock the device and check App Group signing."
        case .invalid: return "Invalid control definition or state. Check IDs, action, type and value bounds."
        case .missing: return "This control was removed. Open HTMLApp and publish it again."
        case .limit: return "This project has reached its control or pending-event limit."
        case .permission: return "Enable this action's permission in HTMLApp, then publish the control again."
        case .unavailable: return "This action is unavailable on this device."
        }
    }
}

enum HTMLAppSystemControlStore {
    static let openRequested = Notification.Name("HTMLApp.SystemControlOpen")
    static let stateChanged = Notification.Name("HTMLApp.SystemControlState")

    static func repository() throws -> HTMLAppSystemControlRepository {
        guard let directory = HTMLAppSharedContainer.directory else { throw HTMLAppSystemControlError.storage }
        return HTMLAppSystemControlRepository(directory: directory)
    }

    static func controls() throws -> [HTMLAppSystemControl] { try repository().read().controls }

    static func publish(appID: String, definitions: [HTMLAppSystemControl], initial: [String: HTMLAppControlValue]) throws {
        guard definitions.count <= 32, initial.count <= 128,
              initial.keys.allSatisfy({ HTMLAppSystemControl.validID($0) }),
              Set(definitions.map(\.controlID)).count == definitions.count,
              definitions.allSatisfy({ $0.appID == appID && $0.isValid }) else { throw HTMLAppSystemControlError.invalid }
        try repository().mutate { document in
            let others = document.controls.filter { $0.appID != appID }
            guard others.count + definitions.count <= 512 else { throw HTMLAppSystemControlError.limit }
            document.controls = others + definitions
            var values = document.values[appID] ?? [:]
            // Re-publication preserves changes made from Control Center.
            for (key, value) in initial where values[key] == nil { values[key] = value }
            for definition in definitions where definition.type == "toggle" {
                guard let key = definition.stateKey else { throw HTMLAppSystemControlError.invalid }
                if values[key] == nil { values[key] = .boolean(false) }
                guard let stored = values[key], case .boolean = stored else { throw HTMLAppSystemControlError.invalid }
            }
            guard values.count <= 128 else { throw HTMLAppSystemControlError.limit }
            document.values[appID] = values
        }
        reload()
    }

    static func set(appID: String, values: [String: HTMLAppControlValue]) throws {
        guard values.keys.allSatisfy({ HTMLAppSystemControl.validID($0) }) else { throw HTMLAppSystemControlError.invalid }
        try repository().mutate { document in
            var updated = document.values[appID] ?? [:]
            updated.merge(values) { _, new in new }
            document.values[appID] = updated
            try validateValues(appID: appID, in: document)
        }
        reload()
        NotificationCenter.default.post(name: stateChanged, object: appID)
    }

    static func validateValues(appID: String, in document: HTMLAppSystemControlDocument) throws {
        let values = document.values[appID] ?? [:]
        guard values.count <= 128 else { throw HTMLAppSystemControlError.limit }
        for control in document.controls where control.appID == appID && control.type == "toggle" {
            guard let key = control.stateKey, let value = values[key], case .boolean = value else { throw HTMLAppSystemControlError.invalid }
        }
    }

    static func append(_ event: HTMLAppSystemControlEvent, to document: inout HTMLAppSystemControlDocument) throws {
        guard document.events.filter({ $0.appID == event.appID }).count < 64 else { throw HTMLAppSystemControlError.limit }
        document.events.append(event)
    }

    static func remove(appID: String) throws {
        try repository().mutate { document in
            document.controls.removeAll { $0.appID == appID }
            document.values.removeValue(forKey: appID)
            document.events.removeAll { $0.appID == appID }
            if document.pendingOpen?.appID == appID { document.pendingOpen = nil }
        }
        reload()
    }

    static func takeOpen() throws -> HTMLAppSystemControlOpen? {
        guard try repository().read().pendingOpen != nil else { return nil }
        return try repository().mutate { document in
            defer { document.pendingOpen = nil }
            guard let open = document.pendingOpen, Date().timeIntervalSince(open.createdAt) < 120,
                  document.controls.contains(where: { $0.appID == open.appID && $0.controlID == open.controlID }) else { return nil }
            return open
        }
    }

    static func reload() {
        if #available(iOS 18.0, *) {
            Task { @MainActor in ControlCenter.shared.reloadAllControls() }
        }
    }
}
