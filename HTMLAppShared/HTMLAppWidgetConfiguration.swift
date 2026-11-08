import AppIntents

/// Shared with the containing app: the system can resolve configuration intents
/// in either process. Keep persisted intent/entity type names and IDs stable.
@available(iOS 17.0, *)
struct HTMLAppWidgetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "HTMLApp Widget"
    static var defaultQuery = HTMLAppWidgetEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

@available(iOS 17.0, *)
struct HTMLAppWidgetEntityQuery: EntityQuery {
    private var choices: [HTMLAppWidgetEntity] {
        do {
            let available = try HTMLAppWidgetStore.readAll().map {
                let appName = $0.appName ?? $0.name
                let title = appName == $0.name ? $0.name : "\(appName) · \($0.name)"
                return HTMLAppWidgetEntity(id: $0.id, name: "\(title) [\($0.appID.prefix(6))]")
            }
            return available
        } catch {
            return []
        }
    }

    func entities(for identifiers: [HTMLAppWidgetEntity.ID]) async throws -> [HTMLAppWidgetEntity] {
        let available = choices
        return identifiers.map { id in
            available.first { $0.id == id } ?? HTMLAppWidgetEntity(id: id, name: "Unavailable widget — choose another HTMLApp")
        }
    }

    func suggestedEntities() async throws -> [HTMLAppWidgetEntity] {
        choices
    }

    func defaultResult() async -> HTMLAppWidgetEntity? {
        choices.first
    }
}

@available(iOS 17.0, *)
struct HTMLAppWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose HTMLApp Widget"
    static var description = IntentDescription("Choose a widget published by one of your saved HTMLApps.")

    @Parameter(title: "Widget")
    var widget: HTMLAppWidgetEntity?
}

