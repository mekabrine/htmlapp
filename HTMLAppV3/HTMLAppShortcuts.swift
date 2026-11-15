import AppIntents
import Foundation
import WidgetKit

@available(iOS 16.2, *)
struct RefreshHTMLAppWidgetDataIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Widget Data"
    static var description = IntentDescription("Refresh saved widget bindings and approved native background data, then ask iOS to reload HTMLApp widgets. This does not run JavaScript in closed HTML apps.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try Task.checkCancellation()
        // Only copy explicitly declared portable-data bindings. Do not change
        // the primary selection or execute generated app code in a shortcut.
        let definitions = try HTMLAppWidgetStore.readAll()
        for appID in Set(definitions.map(\.appID)) {
            let keys = Set(definitions.filter { $0.appID == appID }
                .flatMap { Array(($0.dataBindings ?? [:]).values) })
            for key in keys {
                HTMLAppWidgetStore.updateFromPortableData(appID: appID, key: key,
                    value: HTMLAppPortableDataStore.get(appID: appID, key: key))
            }
        }
        // This is the existing manual-refresh path; it retains saved network
        // consent checks and refreshes native jobs and widget refresh specs.
        _ = await HTMLAppBackgroundCoordinator.shared.runNow()
        try Task.checkCancellation()
        // Direct request so completion does not depend on a delayed coalescer.
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// These intents deliberately hand work to the visible app. Siri/Shortcuts
/// cannot silently execute untrusted generated HTML or run a paid AI request.
@available(iOS 16.2, *)
struct OpenSavedHTMLAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Saved HTML App"
    static var description = IntentDescription("Open an app you've saved in HTMLApp.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "App Name", description: "The name of a saved HTML app")
    var appName: String

    func perform() async throws -> some IntentResult {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw $appName.needsValueError("Which saved app do you want to open?") }
        UserDefaults.standard.set(String(name.prefix(120)), forKey: "htmlapp.shortcut.openName")
        NotificationCenter.default.post(name: Notification.Name("HTMLAppShortcutRequested"), object: nil)
        return .result()
    }
}

@available(iOS 16.2, *)
struct CreateHTMLAppFromPromptIntent: AppIntent {
    static var title: LocalizedStringResource = "Create HTML App with AI"
    static var description = IntentDescription("Open Forge with your idea ready to review and generate.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "App Idea", description: "Describe the app you'd like to create")
    var prompt: String

    func perform() async throws -> some IntentResult {
        let idea = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else { throw $prompt.needsValueError("What should the app do?") }
        UserDefaults.standard.set(String(idea.prefix(4000)), forKey: "htmlapp.shortcut.createPrompt")
        NotificationCenter.default.post(name: Notification.Name("HTMLAppShortcutRequested"), object: nil)
        return .result()
    }
}

@available(iOS 16.2, *)
struct OpenSavedHTMLAppActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Saved HTML App Action"
    static var description = IntentDescription("Open a saved HTML app and deliver an action for it to handle.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "App Name")
    var appName: String

    @Parameter(title: "Action")
    var action: String

    func perform() async throws -> some IntentResult {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !command.isEmpty, command.count <= 120 else {
            throw $action.needsValueError("Provide a saved app and a short action.")
        }
        UserDefaults.standard.set(String(name.prefix(120)), forKey: "htmlapp.shortcut.openName")
        UserDefaults.standard.set(command, forKey: "htmlapp.shortcut.pendingAction")
        NotificationCenter.default.post(name: Notification.Name("HTMLAppShortcutRequested"), object: nil)
        return .result()
    }
}

@available(iOS 16.2, *)
struct HTMLAppSiriShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RefreshHTMLAppWidgetDataIntent(),
            phrases: ["Refresh widgets in \(.applicationName)"],
            shortTitle: "Refresh Widgets",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: OpenSavedHTMLAppIntent(),
            phrases: [
                "Open a saved app in \(.applicationName)",
                "Launch my HTML app with \(.applicationName)"
            ],
            shortTitle: "Open HTML App",
            systemImageName: "apps.iphone"
        )
        AppShortcut(
            intent: OpenSavedHTMLAppActionIntent(),
            phrases: [
                "Run an app action in \(.applicationName)"
            ],
            shortTitle: "Run HTML App Action",
            systemImageName: "play.square"
        )
        AppShortcut(
            intent: CreateHTMLAppFromPromptIntent(),
            phrases: [
                "Create an app with \(.applicationName)",
                "Make an HTML app in \(.applicationName)"
            ],
            shortTitle: "Create with AI",
            systemImageName: "sparkles"
        )
    }
}

