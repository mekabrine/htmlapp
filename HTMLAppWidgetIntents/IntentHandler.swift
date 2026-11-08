import Intents

final class IntentHandler: INExtension, SelectHTMLAppIntentHandling {
    override func handler(for intent: INIntent) -> Any { self }

    func provideWidgetOptionsCollection(for intent: SelectHTMLAppIntent,
        with completion: @escaping (INObjectCollection<PublishedWidget>?, Error?) -> Void) {
        do {
            let definitions = try HTMLAppWidgetStore.readAll()
            let options = definitions.map { definition -> PublishedWidget in
                let app = definition.appName ?? definition.name
                let title = app == definition.name ? app : "\(app) · \(definition.name)"
                return PublishedWidget(identifier: definition.id, display: title)
            }
            completion(INObjectCollection(items: options), nil)
        } catch { completion(nil, error) }
    }
}
