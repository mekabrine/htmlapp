import Foundation

/// Conservative source checks, not proof of arbitrary natural-language intent.
enum ForgeEditAcceptance {
    static func requiresNativeTabs(_ request: String) -> Bool {
        let text = request.lowercased()
        return (text.contains("tab") || text.contains("bottom navigation")) &&
            ["native", "built-in", "built in", "system", "ios"].contains(where: text.contains) &&
            !["remove native", "without native", "don't use native"].contains(where: text.contains)
    }

    static func issues(before: String, after: String, request: String) -> [String] {
        var issues: [String] = []
        func effective(_ source: String) -> String {
            source.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if effective(before) == effective(after) {
            issues.append("Edit acceptance: no effective source change was made.")
        }
        if requiresNativeTabs(request) &&
            after.range(of: #"(?:screens|tabs)\s*\.\s*configure\s*\("#,
                        options: .regularExpression) == nil && !after.contains("htmlapp-navigation") {
            issues.append("Edit acceptance: requested built-in navigation is missing. Configure native screens or declare htmlapp-navigation, preserve destinations, and hide HTML tab fallback after native mount.")
        }
        return issues
    }
}
