import Foundation

/// Detect the opt-in package runtime independent of HTML attribute ordering,
/// quote style and capitalization. A string match silently broke multi-file
/// apps when an AI generated an equally valid meta tag.
enum HTMLAppDocumentMode {
    static func usesPackageRuntime(_ html: String) -> Bool {
        let input: String
        if let head = html.range(of: "<head", options: .caseInsensitive),
           let start = html[head.lowerBound...].firstIndex(of: ">"),
           let end = html.range(of: "</head>", options: .caseInsensitive,
                                   range: html.index(after: start)..<html.endIndex) {
            input = String(html[html.index(after: start)..<end.lowerBound])
        } else {
            input = String(html.prefix(200_000))
        }
        let source = input.replacingOccurrences(of: #"(?s)<!--.*?-->"#,
                                               with: "", options: .regularExpression)
        guard let tagPattern = try? NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: .caseInsensitive),
              let attributePattern = try? NSRegularExpression(
                pattern: #"([A-Za-z_:][A-Za-z0-9_:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)
        else { return false }
        let ns = source as NSString
        for tagMatch in tagPattern.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: tagMatch.range)
            let tagNS = tag as NSString
            var attrs: [String: String] = [:]
            for match in attributePattern.matches(in: tag, range: NSRange(location: 0, length: tagNS.length)) {
                let key = tagNS.substring(with: match.range(at: 1)).lowercased()
                for group in 2...4 where match.range(at: group).location != NSNotFound {
                    attrs[key] = tagNS.substring(with: match.range(at: group))
                    break
                }
            }
            if attrs["name"]?.lowercased() == "htmlapp-runtime",
               attrs["content"]?.lowercased() == "package" { return true }
        }
        return false
    }
}
