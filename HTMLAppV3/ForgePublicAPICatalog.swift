import Foundation

/// Candidate discovery only. Availability, CORS and terms are not guarantees.
enum ForgePublicAPICatalog {
    private static let entries: [[String: Any]] = {
        guard let url = Bundle.main.url(forResource: "htmlapp-api-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return root["apis"] as? [[String: Any]] ?? []
    }()
    static func context(for request: String) -> String {
        let words = Set(request.lowercased().split { !$0.isLetter && !$0.isNumber }
            .map(String.init).filter { $0.count > 2 })
        let ranked = entries.enumerated().compactMap { index, entry -> (Int, Int, [String: Any])? in
            guard entry["verificationStatus"] as? String != "fail" else { return nil }
            let text = ["id", "name", "category", "use"].compactMap { entry[$0] as? String }.joined(separator: " ").lowercased()
            let score = words.filter { text.contains($0) }.count
            guard score > 0 else { return nil }
            return (score, index, entry)
        }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 > $1.0 }.prefix(6)
        guard !ranked.isEmpty else { return "" }
        let candidates = ranked.compactMap { item -> String? in
            guard let data = try? JSONSerialization.data(withJSONObject: item.2, options: [.sortedKeys]) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")
        return """
        PUBLIC API CANDIDATES (not verified capabilities):
        Select only relevant providers. Check official docs, terms, attribution and current behavior. Examples are starting points, never guaranteed contracts. A health check cannot prove licensing or WKWebView CORS compatibility. Handle failures honestly.
        Never embed provider secrets in HTML. Keyed services need backend-managed secrets or explicit user key entry stored with native secure storage. Never log/share keys. Native network.request only supports consented public HTTPS text/JSON without redirects, cookies or binary; it cannot replace WebSocket, tiles, images, OAuth or streaming transports. Respect provider policies and required caching even in network-first mode. Demo sources must be labeled demo. Never invent live results.
        \(candidates)
        """
    }
}
