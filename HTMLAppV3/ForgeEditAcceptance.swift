import Foundation

/// Conservative source checks, not proof of arbitrary natural-language intent.
/// Runtime and model reviews still verify that controls actually work.
enum ForgeEditAcceptance {
    static func requiresNativeTabs(_ request: String) -> Bool {
        let text = request.lowercased()
        return (text.contains("tab") || text.contains("bottom navigation")) &&
            ["native", "built-in", "built in", "system", "ios"].contains(where: text.contains) &&
            !["remove native", "without native", "don't use native"].contains(where: text.contains)
    }

    /// Only count an actual native route with matching destinations, rather
    /// than the phrase "htmlapp-navigation" in a comment or a patch summary.
    static func hasNativeNavigation(_ html: String) -> Bool {
        let pages = attributeValues("data-htmlapp-screen", in: html)
        if let scripts = try? NSRegularExpression(
            pattern: #"<script\b([^>]*)>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let ns = html as NSString
            for match in scripts.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                let tag = ns.substring(with: match.range(at: 1))
                guard attributeValues("id", in: tag).contains("htmlapp-navigation"),
                      attributeValues("type", in: tag).contains("application/json") else { continue }
                let body = ns.substring(with: match.range(at: 2))
                guard let data = body.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["items"] as? [[String: Any]],
                      (2...7).contains(items.count) else { continue }
                let ids = items.compactMap { $0["id"] as? String }
                guard ids.count == items.count,
                      Set(ids).count == ids.count,
                      ids.allSatisfy({ $0.range(of: #"^[A-Za-z][A-Za-z0-9_-]{0,31}$"#,
                                                   options: .regularExpression) != nil }),
                      pages.count == ids.count,
                      Set(pages) == Set(ids) else { continue }
                if let selected = json["selected"] as? String, !ids.contains(selected) { continue }
                return true
            }
        }
        // Custom JS routers are supported, but must expose native
        // configuration plus working destinations or a selection listener.
        guard let call = try? NSRegularExpression(
            pattern: #"\b(?:HTMLAppNative|api)\s*\.\s*(?:screens|tabs)\s*\.\s*configure\s*\("#,
            options: .caseInsensitive),
              call.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) != nil
        else { return false }
        return Set(pages).count >= 2 ||
            html.contains("htmlapp:native-tab-select") ||
            html.contains("tabs.onSelect")
    }

    private static func attributeValues(_ name: String, in text: String) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?:^|\s)"# + escaped + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            for group in 1...3 where match.range(at: group).location != NSNotFound {
                return ns.substring(with: match.range(at: group))
            }
            return nil
        }
    }

    static func issues(before: String, after: String, request: String) -> [String] {
        var issues: [String] = []
        func effective(_ source: String) -> String {
            source.replacingOccurrences(of: #"(?s)<!--.*?-->"#, with: "",
                                        options: .regularExpression)
                .replacingOccurrences(of: "\r\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if effective(before) == effective(after) {
            issues.append("Edit acceptance: no effective source change was made.")
        }
        if requiresNativeTabs(request) && !hasNativeNavigation(after) {
            issues.append("Edit acceptance: requested built-in navigation is missing or invalid. Declare a JSON htmlapp-navigation manifest whose tab IDs match every data-htmlapp-screen, or configure native tabs with working selection handlers; do not substitute a CSS bottom bar.")
        }
        return issues
    }
}
