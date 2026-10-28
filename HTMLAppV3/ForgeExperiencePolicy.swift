import Foundation

enum ForgeBuildStage: Int, CaseIterable {
    case planning, building, checking, ready
    var title: String { ["Planning", "Building", "Checking", "Ready"][rawValue] }
    static func current(phase: String, working: Bool, hasHTML: Bool, failed: Bool = false) -> ForgeBuildStage {
        let phase = phase.lowercased()
        if !working && hasHTML && !failed { return .ready }
        if ["research", "capabil", "planning", "reading your request"].contains(where: phase.contains) { return .planning }
        if ["check", "verif", "repair", "review", "polish"].contains(where: phase.contains) { return .checking }
        if ["generating", "coding", "streaming", "editing", "icon", "asset"].contains(where: phase.contains) { return .building }
        return .planning
    }
}

enum ForgeRecoveryAdvice {
    static func message(for error: String) -> String {
        let text = error.lowercased()
        if ["401", "403", "api key", "not configured", "configure"].contains(where: text.contains) {
            return "Check your provider URL, model and API key in AI Settings, then retry. Your idea and available preview are kept."
        }
        if ["429", "rate limit", "quota", "credit"].contains(where: text.contains) {
            return "Check your provider's usage limit or credits, then retry when available. Your draft is kept. A retry may use more credits."
        }
        if ["network", "offline", "timed out", "connection"].contains(where: text.contains) {
            return "Check your connection and retry. Your idea and available preview are kept. A retry may use more credits."
        }
        return "Your idea and available preview are kept. Retry the failed step, or return to the preview and adjust your request. A retry may use more credits."
    }
}

/// Version trials never receive the saved app's native permissions or data.
enum HTMLAppTrialDocument {
    static func prepare(_ html: String) -> String {
        html.replacingOccurrences(of: "</head>", with: "<script>window.__HTMLAPP_STARTER_PREVIEW__=true;</script></head>", options: .caseInsensitive)
    }
}

