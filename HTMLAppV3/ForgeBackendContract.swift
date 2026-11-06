import Foundation

/// Backend completeness is a correctness requirement, independent of optional UI QA.
enum ForgeBackendContract {
    static let instructions = """
    MANAGED RUNTIME V2 — AUTHORITATIVE BACKEND CAPABILITY:
    HTMLApp can deploy generated Python servers automatically using the owner's saved secret.
    A requested server feature must have real Python, manifest and matching frontend calls.
    Do not replace an external API, cloud storage or multi-user workflow with local storage,
    local notifications, a setup note, placeholder URL, or 'ask an administrator'.
    Backend registration and deployment belong to the native host. No secrets in generated code.
    Bundle transport: inside <htmlapp_code>, put <script type="application/json" id="htmlapp-backend-v2">
    containing {"source":"complete server.py","manifest":{...}}. Escape '<' inside JSON as
    a Unicode escape. Do not emit separate backend artifacts outside the HTML document.
    Use HTMLAppNative.backend.request({path,method,body,session}) for generated routes.
    backend.status() returns linked, sdkVersion, apiBaseURL, canNotify, pushConfigured and state.
    Never gate v2 access on a legacy sendKey. backend.subscribe(session) registers this phone
    for its authenticated resource; unsubscribe(session) removes it. push.register alone does
    not subscribe or deliver anything. Public APIs are deliberate public routes; respect the
    user's authentication requirements while keeping phone registration resource-scoped.
    For an external caller, show the real URL from backend.status().apiBaseURL + route and
    the exact method/body/auth expected by server.py. Never invent an external URL or require
    the VPS provisioning secret or private management key in external integrations.
    Preview is not deployed; show 'Save to activate backend' rather than 'host unsupported'.
    Encryption happens on the client using established cryptography; never upload plaintext
    or decryption passwords. A publishable app key is not private-user authorization.
    Readiness checks are required and must test generated routes, including expected auth failures.
    Preserve the backend bundle and API compatibility during unrelated edits and UI polish.
    """

    static func requiresBackend(request: String, html: String) -> Bool {
        ForgeCapabilityPlan.requiresBackend(request: request, html: html)
    }

    static func issues(request: String, html: String, required: Bool = false) -> [String] {
        guard required || requiresBackend(request: request, html: html) else { return [] }
        do {
            guard let bundle = try HTMLAppRuntimeBundle.extract(html) else {
                return ["Backend required: include the executable v2 Python source and manifest, not a local-only substitute or legacy meta declaration."]
            }
            var result = [String]()
            let frontend = html.replacingOccurrences(of: HTMLAppRuntimeBundle.scriptPattern, with: "", options: [.regularExpression, .caseInsensitive])
            if !frontend.contains("backend.request") && !frontend.contains("backend?.request") {
                result.append("Connect the frontend to the declared server routes using backend.request.")
            }
            let routes = bundle.object["manifest"] as? [String: Any]
            let paths = Set((routes?["routes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String })
            let expression = #"backend\??\.request\s*\(\s*\{[^}]*?path\s*:\s*["']([^"']+)["']"#
            if let regex = try? NSRegularExpression(pattern: expression) {
                for match in regex.matches(in: frontend, range: NSRange(frontend.startIndex..., in: frontend)) {
                    guard let range = Range(match.range(at: 1), in: frontend) else { continue }
                    let path = String(frontend[range]).components(separatedBy: "?")[0]
                    let matched = paths.contains { route in
                        let expected = route.split(separator: "/")
                        let actual = path.split(separator: "/")
                        return expected.count == actual.count && zip(expected, actual).allSatisfy { pair in
                            pair.0 == pair.1 || (pair.0.hasPrefix("{") && pair.0.hasSuffix("}"))
                        }
                    }
                    if !matched {
                        result.append("Frontend route \(path) is absent from the backend manifest.")
                    }
                }
            }
            for placeholder in ["your-relay.example", "your-backend.example", "your-server.example", "https://your-api"] where html.contains(placeholder) {
                result.append("Replace the placeholder backend URL with backend.status().apiBaseURL and a real declared route.")
            }
            return result
        } catch { return ["Repair the runtime bundle: " + error.localizedDescription] }
    }
}
