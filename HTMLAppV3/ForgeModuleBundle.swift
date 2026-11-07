import Foundation

/// Portable multi-file payload retained inside the saved/exported HTML document.
enum ForgeModuleBundle {
    struct Module: Decodable { let path: String; let task: String; let interface: String }
    static func validPath(_ path: String) -> Bool {
        path.hasPrefix("modules/") && path.count < 180 && !path.contains("..") &&
        path.range(of: #"^modules/[A-Za-z0-9_/-]+\.(js|mjs|json|css)$"#, options: .regularExpression) != nil
    }
    static func files(in html: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?s)<script\s+type="application/json"\s+id="htmlapp-files">(.*?)</script>"#),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html),
              let bytes = String(html[range]).data(using: .utf8), bytes.count <= 4_000_000,
              let files = try? JSONDecoder().decode([String: String].self, from: bytes),
              files.count <= 12, files.keys.allSatisfy(validPath) else { return [:] }
        return files
    }
    static func embed(_ files: [String: String], in html: String) throws -> String {
        guard files.count <= 12, files.keys.allSatisfy(validPath) else { throw AIGenerationError.invalidPatch }
        let bytes = try JSONSerialization.data(withJSONObject: files, options: [.sortedKeys])
        guard bytes.count <= 4_000_000, let json = String(data: bytes, encoding: .utf8) else { throw AIGenerationError.invalidPatch }
        let script = "<script type=\"application/json\" id=\"htmlapp-files\">" + json.replacingOccurrences(of: "<", with: "\\u003c") + "</script>"
        let stripped = html.replacingOccurrences(of: #"(?s)<script\s+type="application/json"\s+id="htmlapp-files">.*?</script>"#, with: "", options: .regularExpression)
        guard let end = stripped.range(of: "</head>", options: .caseInsensitive) else { throw AIGenerationError.invalidPatch }
        var result = stripped; result.insert(contentsOf: script, at: end.lowerBound)
        return result
    }
    static func generate(plan: String, html: String, brief: String, config: AIProviderConfiguration) async throws -> String {
        guard let bytes = plan.data(using: .utf8), !plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return html }
        let modules = try JSONDecoder().decode([Module].self, from: bytes)
        guard (1...4).contains(modules.count), Set(modules.map(\.path)).count == modules.count,
              modules.allSatisfy({ validPath($0.path) && !$0.task.isEmpty && !$0.interface.isEmpty }) else { throw AIGenerationError.invalidPatch }
        let files = try await withThrowingTaskGroup(of: (String, String).self) { group in
            for module in modules {
                group.addTask {
                    let source = try await AIProviderClient.complete(config: config,
                        system: "Implement exactly one module for an iOS WKWebView app. Return only raw source, no Markdown fences. Honor every shared interface. No secrets, placeholders or invented native APIs. Use relative module imports and the documented bundled libraries. Do not add dependencies. " + ForgeRuntimeAuthoring.instructions,
                        messages: [("user", "USER OUTCOME:\n" + brief + "\nSHARED MODULE CONTRACT:\n" + plan + "\nHOST HTML:\n" + html + "\nYOUR FILE: " + module.path + "\nTASK: " + module.task + "\nINTERFACE: " + module.interface)],
                        timeout: 120, maxTokens: 12000, retryOnTransient: true)
                    guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !source.hasPrefix("```") else { throw AIGenerationError.invalidPatch }
                    return (module.path, source)
                }
            }
            var result: [String: String] = [:]
            for try await (path, source) in group { result[path] = source }
            return result
        }
        return try embed(files, in: html)
    }
}
