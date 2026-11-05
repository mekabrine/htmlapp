import Foundation

/// Generated bundles are inert JSON. Only the VPS executes their Python source.
struct HTMLAppRuntimeBundle: Codable {
    let source: String
    let manifest: [String: RuntimeJSON]

    static func extract(_ html: String) throws -> Self? {
        let pattern = #"<script\s+type=["']application/json["']\s+id=["']htmlapp-backend-v2["']\s*>([\s\S]*?)</script>"#
        let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            if html.contains("htmlapp-backend-v2") { throw HTMLAppBackendError(message: "The generated backend bundle is malformed. Ask Forge to repair its script tag.") }
            return nil
        }
        let bundle = try JSONDecoder().decode(Self.self, from: Data(html[range].utf8))
        guard bundle.source.utf8.count <= 100_000,
              bundle.manifest["sdkVersion"] == .number(2) else {
            throw HTMLAppBackendError(message: "Invalid runtime bundle or unsupported SDK version.")
        }
        return bundle
    }
    var object: [String: Any] {
        let bytes = try! JSONEncoder().encode(self)
        return try! JSONSerialization.jsonObject(with: bytes) as! [String: Any]
    }
}

indirect enum RuntimeJSON: Codable, Equatable {
    case string(String), number(Double), bool(Bool), array([RuntimeJSON]), object([String: RuntimeJSON]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([RuntimeJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: RuntimeJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

@MainActor
enum HTMLAppRuntimeBackend {
    static func deploy(localID: String, name: String, bundle: HTMLAppRuntimeBundle) async throws {
        let capabilities = try await HTMLAppBackendAPI.raw("/v2/capabilities", method: "GET", key: "")
        guard capabilities["sdkVersion"] as? Int == 2 else { throw HTMLAppBackendError(message: "Your server does not support runtime v2.") }
        let existing = HTMLAppBackendStore.link(for: localID)
        let credential: String
        let path: String
        var body = bundle.object
        if let existing {
            guard !existing.managementKey.isEmpty else { throw HTMLAppBackendError(message: "This shared copy cannot edit its owner’s backend. Create a separately owned app to change its server code.") }
            guard existing.sdkVersion == 2 else { throw HTMLAppBackendError(message: "Create a separate v2 backend before migrating this legacy app.") }
            credential = existing.managementKey
            let details = try await HTMLAppBackendAPI.raw("/v2/manage/apps/" + existing.appID, method: "GET", key: credential)
            body["baseRevision"] = details["revision"]
            path = "/v2/manage/apps/" + existing.appID + "/deploy"
            let deployed = try await HTMLAppBackendAPI.raw("/v2/manage/apps/" + existing.appID + "/source", method: "GET", key: credential)
            if let bytes = try? JSONSerialization.data(withJSONObject: deployed),
               let current = try? JSONDecoder().decode(HTMLAppRuntimeBundle.self, from: bytes),
               current.source == bundle.source && current.manifest == bundle.manifest {
                try Data(bundle.source.utf8).write(to: HTMLAppBackendStore.sourceURL(for: localID), options: [.atomic, .completeFileProtection])
                return
            }
        } else {
            guard let secret = KeychainValueStore.read(account: "backend-provision-key") else {
                throw HTMLAppBackendError(message: "Enter your backend secret in Settings before saving this app.")
            }
            credential = secret
            body["clientID"] = localID
            body["name"] = String(name.prefix(40))
            path = "/v2/deployments"
        }
        let result = try await mutate(path, method: "POST", key: credential, body: body, localID: localID)
        if existing == nil {
            guard let id = result["appID"] as? String, let management = result["managementKey"] as? String,
                  let publicKey = result["publicKey"] as? String else { throw HTMLAppBackendError(message: "Server returned incomplete backend credentials.") }
            try HTMLAppBackendStore.save(HTMLAppBackendLink(appID: id, managementKey: management, readKey: publicKey,
                sendKey: nil, runtimeReadKey: nil, sdkVersion: 2), for: localID)
            // Creation retries can return a previously committed deployment.
            // Reconcile its source before accepting the matching frontend.
            try await deploy(localID: localID, name: name, bundle: bundle)
            return
        }
        try Data(bundle.source.utf8).write(to: HTMLAppBackendStore.sourceURL(for: localID), options: [.atomic, .completeFileProtection])
    }

    static func mutate(_ path: String, method: String, key: String, body: [String: Any]?, localID: String) async throws -> [String: Any] {
        let storage = "htmlapp.runtime.operation." + localID
        let fingerprint = try JSONSerialization.data(withJSONObject: ["path": path, "method": method, "body": body ?? [:]], options: [.sortedKeys])
        let previous = UserDefaults.standard.dictionary(forKey: storage)
        let same = previous?["request"] as? Data == fingerprint
        let idempotency = same ? (previous?["idempotency"] as? String ?? UUID().uuidString) : UUID().uuidString
        UserDefaults.standard.set(["request": fingerprint, "idempotency": idempotency], forKey: storage)
        let pending = try await HTMLAppBackendAPI.raw(path, method: method, key: key, body: body, idempotency: idempotency)
        guard let statusPath = pending["statusURL"] as? String, statusPath.hasPrefix("/v2/operations/"),
              statusPath.range(of: #"^/v2/operations/[a-f0-9]{32}$"#, options: .regularExpression) != nil else {
            throw HTMLAppBackendError(message: "Invalid deployment operation response.")
        }
        for _ in 0..<360 {
            try Task.checkCancellation()
            let status = try await HTMLAppBackendAPI.raw(statusPath, method: "GET", key: key)
            if status["state"] as? String == "succeeded", let result = status["result"] as? [String: Any] {
                UserDefaults.standard.removeObject(forKey: storage)
                return result
            }
            if status["state"] as? String == "failed" {
                UserDefaults.standard.removeObject(forKey: storage)
                throw HTMLAppBackendError(message: (status["result"] as? [String: Any])?["error"] as? String ?? "Deployment failed. Your previous backend was retained.", status: (status["result"] as? [String: Any])?["status"] as? Int)
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw HTMLAppBackendError(message: "Deployment is still pending. Retry to resume checking its result.")
    }
}

extension HTMLAppRuntimeBackend {
    static func sharedHTML(_ html: String, localID: String) -> String {
        let pattern = #"<script\s+type=["']application/json["']\s+id=["']htmlapp-backend-v2["']\s*>[\s\S]*?</script>"#
        let clean = html.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        guard let link = HTMLAppBackendStore.link(for: localID), link.sdkVersion == 2 else { return clean }
        let publicLink = HTMLAppBackendLink(appID: link.appID, managementKey: "", readKey: link.readKey, sendKey: nil, runtimeReadKey: nil, sdkVersion: 2)
        guard let data = try? JSONEncoder().encode(publicLink) else { return clean }
        return clean + "\n<!--HTMLAPP_RUNTIME:" + data.base64EncodedString() + "-->"
    }
    static func importPublicLink(_ html: String, localID: String) {
        let pattern = #"<!--HTMLAPP_RUNTIME:([A-Za-z0-9+/=]+)-->"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html), let data = Data(base64Encoded: String(html[range])),
              let link = try? JSONDecoder().decode(HTMLAppBackendLink.self, from: data), link.sdkVersion == 2,
              link.managementKey.isEmpty else { return }
        try? HTMLAppBackendStore.save(link, for: localID)
    }
}

@MainActor
enum HTMLAppRuntimeSubscriptions {
    private static let account = "backend-runtime-subscriptions"
    private static var refreshing = false
    private static var subscriptions: [String: String] {
        get {
            guard let text = KeychainValueStore.read(account: account), let value = try? JSONDecoder().decode([String: String].self, from: Data(text.utf8)) else { return [:] }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { KeychainValueStore.write(String(decoding: data, as: UTF8.self), account: account) }
        }
    }
    static func remember(localID: String, session: String, remove: Bool) {
        var values = subscriptions
        let key = localID + ":" + session
        if remove { values.removeValue(forKey: key) } else { values[key] = localID }
        subscriptions = values
    }
    static func refresh() async {
        guard !refreshing, let token = UserDefaults.standard.string(forKey: "htmlapp.apnsToken") else { return }
        refreshing = true
        defer { refreshing = false }
        for (key, localID) in subscriptions {
            guard let link = HTMLAppBackendStore.link(for: localID), link.sdkVersion == 2 else { continue }
            let session = String(key.dropFirst(localID.count + 1))
            do {
                _ = try await HTMLAppBackendAPI.raw("/v2/apps/" + link.appID + "/devices", method: "PUT", key: link.readKey, body: ["session": session, "deviceToken": token])
            } catch {
                if (error as? HTMLAppBackendError)?.status == 401 { remember(localID: localID, session: session, remove: true) }
            }
        }
    }
}
