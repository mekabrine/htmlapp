import Foundation

/// Detect the opt-in package runtime independent of HTML attribute ordering,
/// quote style and capitalization. A string match silently broke multi-file
/// apps when an AI generated an equally valid meta tag.
enum HTMLAppDocumentMode {
    // Consume comments and raw-text elements so examples inside inline scripts
    // or styles are never rewritten as resource tags.
    private static let resourceTags = try! NSRegularExpression(
        pattern: #"<!--.*?(?:-->|$)|<(script|style|textarea|title)(?=[\s/>])((?:"[^"]*"|'[^']*'|[^'">])*)>.*?(?:</\1\s*>|$)|<(link)(?=[\s/>])((?:"[^"]*"|'[^']*'|[^'">])*)>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let attributes = try! NSRegularExpression(
        pattern: #"([^\s=/<>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?"#
    )

    private static func libraryReferences(in html: String) -> [(range: NSRange, url: String)] {
        let source = html as NSString
        return resourceTags.matches(in: html, range: NSRange(location: 0, length: source.length)).compactMap { tag in
            let isLink = tag.range(at: 3).location != NSNotFound
            guard isLink || (tag.range(at: 1).location != NSNotFound &&
                source.substring(with: tag.range(at: 1)).lowercased() == "script") else { return nil }
            let matches = attributes.matches(in: html, range: tag.range(at: isLink ? 4 : 2))
            if isLink {
                guard matches.contains(where: { match in
                    guard source.substring(with: match.range(at: 1)).lowercased() == "rel",
                          let value = (2...4).map({ match.range(at: $0) }).first(where: { $0.location != NSNotFound }) else { return false }
                    return source.substring(with: value).lowercased().split(whereSeparator: \.isWhitespace).contains("stylesheet")
                }) else { return nil }
            }
            guard let attribute = matches.first(where: {
                source.substring(with: $0.range(at: 1)).lowercased() == (isLink ? "href" : "src")
            }), let value = (2...4).map({ attribute.range(at: $0) }).first(where: { $0.location != NSNotFound }) else { return nil }
            return (value, source.substring(with: value))
        }
    }

    static func resolvingBundledLibraries(in html: String, origin: String) -> String {
        guard html.contains("/libraries/") else { return html }
        return replacingLibraryReferences(in: html) { url in
            url.hasPrefix("/libraries/") ? origin + url : nil
        }
    }

    static func replacingLibraryReferences(in html: String, resolve: (String) -> String?) -> String {
        let result = NSMutableString(string: html)
        for reference in libraryReferences(in: html).reversed() {
            if let replacement = resolve(reference.url) {
                result.replaceCharacters(in: reference.range, with: replacement)
            }
        }
        return result as String
    }

    static func remoteLibraries(in html: String) -> [String] {
        libraryReferences(in: html).compactMap { reference in
            guard let url = URL(string: reference.url), url.scheme?.lowercased() == "https",
                  url.host != nil, url.user == nil, url.password == nil else { return nil }
            return url.absoluteString
        }
    }

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
