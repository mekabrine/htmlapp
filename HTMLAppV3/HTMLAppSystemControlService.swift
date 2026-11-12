import Foundation
import UIKit

@available(iOS 16.2, *)
enum HTMLAppSystemControlService {
    struct Publication {
        var definitions: [HTMLAppSystemControl]
        var initial: [String: HTMLAppControlValue]
        var permissions: [HTMLPermission]
    }

    static func parse(appID: String, args: [String: Any]) throws -> Publication {
        guard let raw = args["controls"] as? [[String: Any]], raw.count <= 32 else { throw HTMLAppSystemControlError.invalid }
        let appName = String((args["appName"] as? String ?? appID).prefix(100))
        var permissions = Set<String>()
        let definitions = try raw.map { input -> HTMLAppSystemControl in
            guard let id = input["id"] as? String,
                  let title = input["title"] as? String,
                  let type = input["type"] as? String else { throw HTMLAppSystemControlError.invalid }
            let action: HTMLAppSystemControlAction?
            if let raw = input["action"] {
                guard let rawAction = raw as? [String: Any] else { throw HTMLAppSystemControlError.invalid }
                let data = try JSONSerialization.data(withJSONObject: rawAction)
                action = try JSONDecoder().decode(HTMLAppSystemControlAction.self, from: data)
            } else { action = nil }
            if action?.kind.hasPrefix("activity.") == true { permissions.insert("liveActivities") }
            if action?.kind.hasPrefix("notification.") == true { permissions.insert("notifications") }
            let supplied = input["systemSymbol"] as? String ?? "square.grid.2x2"
            let symbol = UIImage(systemName: supplied) == nil ? "square.grid.2x2" : supplied
            let activity: Data?
            if ["activity.start", "activity.update"].contains(action?.kind ?? ""), let source = input["activity"] as? [String: Any] {
                activity = try HTMLAppLiveActivityService.controlTemplate(appID: appID, args: source)
            } else {
                guard input["activity"] == nil else { throw HTMLAppSystemControlError.invalid }
                activity = nil
            }
            let definition = HTMLAppSystemControl(appID: appID, appName: appName, controlID: id,
                title: title, systemSymbol: symbol, type: type, stateKey: input["stateKey"] as? String,
                action: action, activity: activity)
            guard definition.isValid else { throw HTMLAppSystemControlError.invalid }
            return definition
        }
        guard Set(definitions.map(\.controlID)).count == definitions.count else { throw HTMLAppSystemControlError.invalid }
        let initial = try values(args["initial"] ?? [String: Any]())
        return Publication(definitions: definitions, initial: initial,
            permissions: permissions.sorted().compactMap(HTMLPermission.init(rawValue:)))
    }

    static func values(_ object: Any) throws -> [String: HTMLAppControlValue] {
        guard let object = object as? [String: Any], object.count <= 128,
              object.keys.allSatisfy({ HTMLAppSystemControl.validID($0) }) else { throw HTMLAppSystemControlError.invalid }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode([String: HTMLAppControlValue].self, from: data)
    }

    static func snapshot(appID: String) throws -> [String: Any] {
        let document = try HTMLAppSystemControlStore.repository().read()
        return snapshot(appID: appID, document: document)
    }

    static func snapshot(appID: String, document: HTMLAppSystemControlDocument) -> [String: Any] {
        let definitions = document.controls.filter { $0.appID == appID }
        // Return the public definition fields without exposing compiled activity
        // payloads or other projects' controls, values or pending events.
        let controls: [[String: Any]] = definitions.map { control in
            var data: [String: Any] = ["id": control.controlID, "title": control.title,
                "type": control.type, "systemSymbol": control.systemSymbol]
            data["stateKey"] = control.stateKey
            data["action"] = control.action?.kind
            return data
        }
        let events: [[String: Any]] = document.events.filter { $0.appID == appID }.map { event in
            var data: [String: Any] = ["id": event.id, "controlID": event.controlID,
                "action": event.action, "timestampMs": event.date.timeIntervalSince1970 * 1000]
            data["key"] = event.key
            data["value"] = event.value?.object
            return data
        }
        return ["controls": controls,
                "values": (document.values[appID] ?? [:]).mapValues(\.object), "events": events]
    }
}
