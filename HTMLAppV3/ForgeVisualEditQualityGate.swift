import Foundation

/// A deterministic guard for common visual edits that are syntactically valid
/// but visibly break an existing form. It never claims to replace screenshot
/// comparison on a physical device.
enum ForgeVisualEditQualityGate {
    static func isVisualRequest(_ request: String) -> Bool {
        let lower = request.lowercased()
        return [
            "redesign", "re-design", "redo", "restyle", "rework",
            "appearance", "visual", "look", "layout", "popup", "pop-up",
            "dialog", "modal", "colors", "spacing", "make it prettier",
            "make it cleaner", "ui", "interface"
        ].contains { lower.contains($0) }
    }

    static func targetHint(html: String, request: String) -> String {
        guard isVisualRequest(request) else { return "" }
        let lower = request.lowercased()
        guard ["popup", "pop-up", "dialog", "modal", "sheet"].contains(where: lower.contains) else {
            return ""
        }
        let pattern = #"<(?:dialog|form)\b[^>]*\bid\s*=\s*["']([^"']+)["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return "" }
        let source = html as NSString
        let ids = regex.matches(in: html, range: NSRange(location: 0, length: source.length))
            .compactMap { $0.range(at: 1).location != NSNotFound ? source.substring(with: $0.range(at: 1)) : nil }
        guard !ids.isEmpty else { return "" }
        return """
        TARGETED POPUP / DIALOG ELEMENT IDS FOUND IN ACTUAL SOURCE: \(ids.map { "#" + $0 }.joined(separator: ", ")).
        For a visual redesign, change the effective layout, not merely append another decorative stylesheet.
        An HTML form with separate sibling <label> and <input> elements MUST NOT
        become a two-column CSS grid: that puts labels beside the wrong fields.
        Keep each label above its field, or introduce semantic grouped wrappers
        without changing existing IDs, input names, handlers, or storage.
        Never duplicate visible descriptive copy using ::before/::after content
        when it already appears in the document.
        """
    }

    static func issue(before: String, after: String, request: String) -> String? {
        guard isVisualRequest(request) else { return nil }
        guard before != after else { return "The proposed visual edit made no source change." }
        let pattern = #"<form\b[^>]*\bid\s*=\s*["']([^"']+)["'][^>]*>(.*?)</form>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let text = after as NSString
        for match in regex.matches(in: after, range: NSRange(location: 0, length: text.length)) {
            let id = text.substring(with: match.range(at: 1))
            let inner = text.substring(with: match.range(at: 2))
            // This specifically detects labels and controls which are direct
            // siblings rather than a grouped form-field component.
            guard inner.range(
                of: #"</label>\s*<(?:input|textarea|select)\b"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil else { continue }
            let selector = NSRegularExpression.escapedPattern(for: id)
            let rulePattern = "#\(selector)\\s*\\{([^}]*)\\}"
            guard let rules = try? NSRegularExpression(
                pattern: rulePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else { continue }
            let declarations = rules.matches(in: after,
                range: NSRange(location: 0, length: text.length))
                .map { text.substring(with: $0.range(at: 1)).lowercased() }
            let introducedGrid = declarations.contains { $0.range(
                of: #"display\s*:\s*grid\b"#, options: .regularExpression
            ) != nil }
            let columns = declarations.contains { body in
                guard let range = body.range(
                    of: #"grid-template-columns\s*:\s*([^;}]+)"#,
                    options: .regularExpression
                ) else { return false }
                let value = String(body[range]).replacingOccurrences(
                    of: #"^grid-template-columns\s*:\s*"#, with: "",
                    options: .regularExpression
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.contains(" 1fr") || value.contains("minmax(") ||
                       value.contains("repeat(") || value.contains("50%") ||
                       value.contains(" 50%")
            }
            if introducedGrid && columns {
                return "The form #\(id) has separate sibling labels and fields, but the redesign gives it multiple grid columns. This misaligns labels, inputs and reminder controls. Use a single-column field stack or add proper grouped wrappers while preserving IDs and behaviors."
            }
        }
        // Avoid printing a duplicate decorative subtitle on top of an already
        // visible description in a dialog.
        if after.contains("modal-copy"),
           after.range(of: #"#[A-Za-z][\w-]*::after\s*\{[^}]*content\s*:\s*["'][^"']{16,}"#,
                       options: [.regularExpression, .caseInsensitive]) != nil,
           !before.contains("::after") {
            return "The redesign adds long text using a pseudo-element even though the dialog already has visible helper text. Style the existing copy instead of duplicating it."
        }
        return nil
    }
}
