import Foundation

/// Deterministic edit checks. Source evidence is necessary, not proof of runtime behavior;
/// the separate runtime and AI outcome reviews still check actual navigation.
enum ForgeEditAcceptance {
    static func requiresNativeTabs(_ request: String) -> Bool {
        let text = request.lowercased()
        let refersToNavigation = ["tab", "bottom navigation", "bottom bar", "navigation bar"]
            .contains(where: text.contains)
        let wantsSystemUI = ["native", "built-in", "built in", "system", "ios", "apple", "real tab"]
            .contains(where: text.contains)
        let explicitlyRejectsSystemUI = [
            "remove native", "without native", "don't use native", "do not use native",
            "no native tab", "remove built-in", "remove built in", "without system tabs"
        ].contains(where: text.contains)
        return refersToNavigation && wantsSystemUI && !explicitlyRejectsSystemUI
    }

    private static func captures(_ pattern: String, from source: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        return expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
            .compactMap { match in
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: source) else { return nil }
                return String(source[range])
            }
    }

    private static func manifestIssues(in html: String) -> [String] {
        let scripts = captures(
            #"<script\b(?=[^>]*\bid\s*=\s*["']htmlapp-navigation["'])(?=[^>]*\btype\s*=\s*["']application/json["'])[^>]*>(.*?)</script\s*>"#,
            from: html
        )
        guard scripts.count == 1,
              let bytes = scripts[0].data(using: .utf8),
              let manifest = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              let items = manifest["items"] as? [[String: Any]],
              (1...7).contains(items.count) else {
            return ["Edit acceptance: built-in navigation requires exactly one valid htmlapp-navigation JSON manifest with 1–7 items."]
        }
        let ids = items.compactMap { $0["id"] as? String }
        let asciiID = try? NSRegularExpression(pattern: #"^[a-zA-Z0-9_-]{1,48}$"#)
        guard ids.count == items.count, Set(ids).count == ids.count,
              ids.allSatisfy({ id in asciiID?.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil }),
              items.allSatisfy({
                  !($0["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  !($0["symbol"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              manifest["selected"].map({ ($0 as? String).map(Set(ids).contains) ?? false }) ?? true else {
            return ["Edit acceptance: native navigation items need unique safe IDs, visible titles, symbols, and a valid selected ID."]
        }
        let screenIDs = captures(
            #"<(?:section|main|div)\b[^>]*\bdata-htmlapp-screen\s*=\s*["']([^"']+)["']"#,
            from: html
        )
        guard screenIDs.count == ids.count, Set(screenIDs) == Set(ids) else {
            return ["Edit acceptance: every native tab ID must match exactly one real data-htmlapp-screen section."]
        }
        return []
    }

    static func issues(before: String, after: String, request: String) -> [String] {
        var issues: [String] = []
        if before.trimmingCharacters(in: .whitespacesAndNewlines) ==
            after.trimmingCharacters(in: .whitespacesAndNewlines) {
            issues.append("Edit acceptance: no effective source change was made.")
        }
        guard requiresNativeTabs(request) else { return issues }

        if after.contains("htmlapp-navigation") {
            issues.append(contentsOf: manifestIssues(in: after))
        } else if after.range(of: #"(?:screens|tabs)\s*\.\s*configure\s*\("#,
                              options: .regularExpression) == nil {
            issues.append("Edit acceptance: requested built-in navigation is missing. Use a valid htmlapp-navigation manifest or configure native screens, preserve destinations, and hide HTML fallback after native mount.")
        }
        return issues
    }
}
