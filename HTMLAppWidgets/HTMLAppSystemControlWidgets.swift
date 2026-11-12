import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct HTMLAppButtonControlValue {
    var definition: HTMLAppSystemControl?
    var entity: HTMLAppSystemControlEntity?
    var title: String { definition?.title ?? entity?.name ?? "Choose an HTMLApp button" }
    var symbol: String { definition?.systemSymbol ?? "square.grid.2x2" }
}

@available(iOS 18.0, *)
struct HTMLAppButtonControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: HTMLAppButtonConfiguration) -> HTMLAppButtonControlValue {
        HTMLAppButtonControlValue(entity: configuration.control)
    }
    func currentValue(configuration: HTMLAppButtonConfiguration) async throws -> HTMLAppButtonControlValue {
        guard let entity = configuration.control else { return HTMLAppButtonControlValue() }
        let control = try HTMLAppSystemControlStore.controls().first { $0.id == entity.id && $0.type == "button" && $0.action?.kind != "open" }
        return HTMLAppButtonControlValue(definition: control, entity: entity)
    }
}

@available(iOS 18.0, *)
struct HTMLAppButtonControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "HTMLAppButtonControl", provider: HTMLAppButtonControlProvider()) { value in
            ControlWidgetButton(action: HTMLAppRunSystemControlIntent(controlID: value.definition?.id ?? "")) {
                Label(value.definition == nil && value.entity != nil ? "Unavailable — republish in HTMLApp" : value.title,
                      systemImage: value.symbol)
            }
        }
        .displayName("HTMLApp Button")
        .description("Run an action from a saved HTMLApp. Choose a project and button after adding it.")
        .promptsForUserConfiguration()
    }
}

@available(iOS 18.0, *)
struct HTMLAppOpenControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: HTMLAppOpenConfiguration) -> HTMLAppButtonControlValue {
        HTMLAppButtonControlValue(entity: configuration.control)
    }
    func currentValue(configuration: HTMLAppOpenConfiguration) async throws -> HTMLAppButtonControlValue {
        guard let entity = configuration.control else { return HTMLAppButtonControlValue() }
        let definition = try HTMLAppSystemControlStore.controls().first { $0.id == entity.id && $0.action?.kind == "open" }
        return HTMLAppButtonControlValue(definition: definition, entity: entity)
    }
}

@available(iOS 18.0, *)
struct HTMLAppOpenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "HTMLAppOpenControl", provider: HTMLAppOpenControlProvider()) { value in
            ControlWidgetButton(action: HTMLAppOpenSystemControlIntent(control:
                value.entity ?? HTMLAppSystemControlEntity(id: "", name: "Choose an HTMLApp"))) {
                Label(value.definition?.title ?? "Choose an HTMLApp", systemImage: value.symbol)
            }
        }
        .displayName("HTMLApp Open")
        .description("Open a saved HTMLApp or one of its screens. Choose a project destination after adding it.")
        .promptsForUserConfiguration()
    }
}

@available(iOS 18.0, *)
struct HTMLAppToggleControlValue {
    var definition: HTMLAppSystemControl? = nil
    var isOn = false
}

@available(iOS 18.0, *)
struct HTMLAppToggleControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: HTMLAppToggleConfiguration) -> HTMLAppToggleControlValue {
        HTMLAppToggleControlValue()
    }
    func currentValue(configuration: HTMLAppToggleConfiguration) async throws -> HTMLAppToggleControlValue {
        guard let selected = configuration.control else { return HTMLAppToggleControlValue() }
        let document = try HTMLAppSystemControlStore.repository().read()
        guard let definition = document.controls.first(where: { $0.id == selected.id && $0.type == "toggle" }),
              let key = definition.stateKey else { return HTMLAppToggleControlValue() }
        let flag: Bool
        if let stored = document.values[definition.appID]?[key], case .boolean(let value) = stored { flag = value }
        else { flag = false }
        return HTMLAppToggleControlValue(definition: definition, isOn: flag)
    }
}

@available(iOS 18.0, *)
struct HTMLAppToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "HTMLAppToggleControl", provider: HTMLAppToggleControlProvider()) { value in
            ControlWidgetToggle(isOn: value.isOn,
                action: HTMLAppSetSystemControlIntent(controlID: value.definition?.id ?? "")) {
                Label(value.definition?.title ?? "Choose an HTMLApp toggle",
                      systemImage: value.definition?.systemSymbol ?? "switch.2")
            }
        }
        .displayName("HTMLApp Toggle")
        .description("Change a saved project's setting without opening it. Add multiple toggles for different HTMLApps.")
        .promptsForUserConfiguration()
    }
}
