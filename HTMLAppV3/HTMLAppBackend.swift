import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LocalAuthentication
import CryptoKit

/// Deliberately separate from SavedHTMLApp, its backup schema and its export files.
struct HTMLAppBackendLink: Codable {
    let appID: String
    let managementKey: String
    let readKey: String
    let sendKey: String?
    let runtimeReadKey: String?
    var sdkVersion: Int? = nil

    var isValid: Bool {
        appID.range(of: #"^[A-Z2-7]{12}$"#, options: .regularExpression) != nil
            && (Self.isKey(managementKey, length: 20) || (sdkVersion == 2 && managementKey.isEmpty))
            && Self.isKey(readKey, length: 32)
            && (sendKey.map { Self.isKey($0, length: 32) } ?? true)
            && (runtimeReadKey.map { Self.isKey($0, length: 32) } ?? true)
    }

    private static func isKey(_ value: String, length: Int) -> Bool {
        value.utf8.count == length
            && value.utf8.allSatisfy {
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
            }
    }
}

struct HTMLAppBackendError: LocalizedError {
    let message: String
    var status: Int? = nil
    var errorDescription: String? { message }
}

enum HTMLAppBackendStore {
    private static let prefix = "backend-link."

    static func link(for appID: String) -> HTMLAppBackendLink? {
        guard let stored = KeychainValueStore.read(account: prefix + appID),
              let link = try? JSONDecoder().decode(HTMLAppBackendLink.self, from: Data(stored.utf8)),
              link.isValid else { return nil }
        return link
    }

    static func save(_ link: HTMLAppBackendLink, for appID: String) throws {
        guard link.isValid else { throw HTMLAppBackendError(message: "This backend link has invalid credentials.") }
        UserDefaults.standard.set(appID, forKey: "htmlapp.runtime.localID." + link.appID)
        let encoded = try JSONEncoder().encode(link)
        KeychainValueStore.write(String(decoding: encoded, as: UTF8.self), account: prefix + appID)
        guard self.link(for: appID)?.managementKey == link.managementKey else {
            throw HTMLAppBackendError(message: "The device could not save the backend credentials.")
        }
    }

    static func unlink(_ appID: String) {
        KeychainValueStore.delete(account: prefix + appID)
        removeSource(appID)
    }

    static func removeSource(_ appID: String) {
        if let url = try? sourceURL(for: appID) { try? FileManager.default.removeItem(at: url) }
    }

    static func sourceURL(for appID: String) throws -> URL {
        var folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
            .appendingPathComponent("PrivateBackendSources", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try folder.setResourceValues(resources)
        let hash = SHA256.hash(data: Data(appID.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(hash + ".py")
    }
}

@MainActor
enum HTMLAppBackendDeletionQueue {
    private static let queueKey = "htmlapp.backend.pendingDeletion"
    private static var flushing = false

    static func isQueued(_ appID: String) -> Bool {
        UserDefaults.standard.stringArray(forKey: queueKey)?.contains(appID) == true
    }

    static func containsBackend(_ backendID: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: queueKey) ?? [])
            .contains { HTMLAppBackendStore.link(for: $0)?.appID == backendID }
    }

    static func enqueue(_ appID: String) {
        guard let link = HTMLAppBackendStore.link(for: appID), !link.managementKey.isEmpty else { return }
        let pending = Set(UserDefaults.standard.stringArray(forKey: queueKey) ?? [])
        UserDefaults.standard.set(Array(pending.union([appID])), forKey: queueKey)
        HTMLAppBackendStore.removeSource(appID)
        Task { await flush() }
    }

    static func flush() async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        for appID in UserDefaults.standard.stringArray(forKey: queueKey) ?? [] {
            guard let link = HTMLAppBackendStore.link(for: appID) else { continue }
            do {
                let result: [String: Any]
                if link.sdkVersion == 2 {
                    result = try await HTMLAppRuntimeBackend.mutate("/v2/manage/apps/" + link.appID, method: "DELETE", key: link.managementKey, body: nil, localID: appID + ".delete")
                } else {
                    result = try await HTMLAppBackendAPI.request(link, path: "", method: "DELETE", key: link.managementKey)
                }
                guard result["deleted"] as? Bool == true else { continue }
                HTMLAppBackendStore.unlink(appID)
                let pending = UserDefaults.standard.stringArray(forKey: queueKey) ?? []
                UserDefaults.standard.set(pending.filter { $0 != appID }, forKey: queueKey)
            } catch {
                // Keep both the queue entry and its key until the gateway confirms deletion.
                continue
            }
        }
    }
}

private final class HTMLAppBackendNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum HTMLAppBackendAPI {
    static let origin = "https://htmlapp.hostish.site"
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config, delegate: HTMLAppBackendNoRedirect(), delegateQueue: nil)
    }()

    static func url(_ link: HTMLAppBackendLink, path: String = "") -> URL {
        URL(string: origin + "/v1/apps/" + link.appID + path)!
    }

    static func request(_ link: HTMLAppBackendLink, path: String, method: String, key: String,
                        body: [String: Any]? = nil) async throws -> [String: Any] {
        guard link.isValid, ["", "/data", "/device", "/notify", "/deploy"].contains(path) else {
            throw HTMLAppBackendError(message: "Invalid backend link or endpoint.")
        }
        return try await authenticatedRequest(url(link, path: path), method: method, key: key, body: body)
    }

    static func raw(_ path: String, method: String, key: String, body: [String: Any]? = nil, idempotency: String? = nil) async throws -> [String: Any] {
        guard path.hasPrefix("/v2/"), !path.contains(".."), !path.contains("#") else { throw HTMLAppBackendError(message: "Invalid runtime endpoint.") }
        return try await authenticatedRequest(URL(string: origin + path)!, method: method, key: key, body: body, idempotency: idempotency)
    }
    static func runtimeRequest(_ link: HTMLAppBackendLink, path: String, method: String, body: [String: Any]?, session: String?) async throws -> [String: Any] {
        try await authenticatedRequest(URL(string: origin + "/v2/apps/" + link.appID + "/api" + path)!, method: method, key: link.readKey, body: body, runtimeSession: session)
    }
    static func pair(_ key: String) async throws {
        _ = try await raw("/v2/enrollment", method: "GET", key: key)
    }
    static func pairLegacy(_ key: String) async throws {
        _ = try await authenticatedRequest(URL(string: origin + "/v1/provision/status")!,
                                           method: "GET", key: key, body: nil)
    }

    static func provision(clientID: String, name: String, template: String, key: String) async throws -> HTMLAppBackendLink {
        let json = try await authenticatedRequest(URL(string: origin + "/v1/provision")!,
            method: "POST", key: key, body: ["clientID": clientID, "name": name, "template": template])
        let link = try JSONDecoder().decode(HTMLAppBackendLink.self, from: JSONSerialization.data(withJSONObject: json))
        guard link.isValid else { throw HTMLAppBackendError(message: "The gateway returned invalid credentials.") }
        return link
    }

    static func authenticatedRequest(_ url: URL, method: String, key: String,
                                             body: [String: Any]?, idempotency: String? = nil, runtimeSession: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let idempotency { request.setValue(idempotency, forHTTPHeaderField: "Idempotency-Key") }
        if let runtimeSession { request.setValue(runtimeSession, forHTTPHeaderField: "X-HTMLApp-Session") }
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 3_000_000,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HTMLAppBackendError(message: "The Hostish gateway did not return a valid reply.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTMLAppBackendError(message: (json["error"] as? String).map { String($0.prefix(180)) }
                                       ?? "The backend rejected the request (HTTP \(http.statusCode)).", status: http.statusCode)
        }
        return json
    }

    static func runtimeStatus(_ link: HTMLAppBackendLink) async throws -> [String: Any] {
        let capability = try await raw("/v2/capabilities", method: "GET", key: "")
        guard capability["sdkVersion"] as? Int == 2 else { throw HTMLAppBackendError(message: "The server does not support runtime v2.") }
        let state: String
        if link.managementKey.isEmpty {
            _ = try await raw("/v2/apps/" + link.appID + "/schema", method: "GET", key: link.readKey)
            state = "connected"
        } else {
            let details = try await raw("/v2/manage/apps/" + link.appID, method: "GET", key: link.managementKey)
            state = details["state"] as? String ?? "unknown"
        }
        let push = capability["pushConfigured"] as? Bool ?? false
        return ["linked": true, "sdkVersion": 2, "apiBaseURL": origin + "/v2/apps/" + link.appID + "/api",
                "canNotify": push, "pushConfigured": push, "state": state, "publicKey": link.readKey]
    }

    static func status(_ link: HTMLAppBackendLink) async throws -> HTMLAppBackendStatus {
        if link.sdkVersion == 2 {
            if link.managementKey.isEmpty {
                let details = try await runtimeStatus(link)
                return HTMLAppBackendStatus(name: "Shared backend", template: "Python v2", revision: 0, publishRead: false,
                    pushConfigured: details["pushConfigured"] as? Bool ?? false, deviceRegistered: false)
            }
            let result = try await raw("/v2/manage/apps/" + link.appID, method: "GET", key: link.managementKey)
            return HTMLAppBackendStatus(name: result["name"] as? String ?? "Backend", template: "Python v2", revision: result["revision"] as? Int ?? 0, publishRead: false, pushConfigured: result["pushConfigured"] as? Bool ?? false, deviceRegistered: false)
        }
        let result = try await request(link, path: "", method: "GET", key: link.managementKey)
        guard let template = result["template"] as? String, ["document", "notification"].contains(template),
              let revision = result["revision"] as? Int,
              let name = result["name"] as? String, result["appID"] as? String == link.appID else {
            throw HTMLAppBackendError(message: "The gateway returned unexpected backend details.")
        }
        return HTMLAppBackendStatus(name: name, template: template, revision: revision,
                                    publishRead: result["publishRead"] as? Bool ?? false,
                                    pushConfigured: result["pushConfigured"] as? Bool ?? false,
                                    deviceRegistered: result["deviceRegistered"] as? Bool ?? false)
    }

    static func send(_ link: HTMLAppBackendLink, title: String, body: String) async throws -> [String: Any] {
        guard let key = link.sendKey else {
            throw HTMLAppBackendError(message: "Link a notification backend with a send key.")
        }
        guard title.utf8.count <= 150, body.utf8.count <= 900,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HTMLAppBackendError(message: "Enter a short notification title and message.")
        }
        return try await request(link, path: "/notify", method: "POST", key: key, body: ["title": title, "body": body])
    }
}

struct HTMLAppBackendStatus {
    let name: String
    let template: String
    let revision: Int
    let publishRead: Bool
    let pushConfigured: Bool
    let deviceRegistered: Bool
}

@MainActor
struct HTMLAppBackendView: View {
    let app: SavedHTMLApp
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var link: HTMLAppBackendLink?
    @State private var backend: HTMLAppBackendStatus?
    @State private var provisioning = ""
    @State private var message: String?
    @State private var busy = false
    @State private var showKey = false
    @State private var importing = false
    @State private var showSource = false
    @State private var confirmUnlink = false
    @State private var source: String?
    @State private var shareURL: URL?
    @State private var dataDraft = ""
    @State private var dataEditor = false
    @State private var repairingBackend = false

    var body: some View {
        NavigationStack {
            Form {
                if let link {
                    Section("Backend details") {
                        LabeledContent("Backend ID", value: link.appID)
                        if link.sdkVersion == 2 {
                            Text(HTMLAppBackendAPI.origin + "/v2/apps/" + link.appID + "/api").textSelection(.enabled)
                            Text(link.managementKey.isEmpty ? "Shared participant access" : "Owner access")
                        }
                        Button("Copy Backend ID") { UIPasteboard.general.string = link.appID }
                        if let backend {
                            LabeledContent("Name", value: backend.name)
                            LabeledContent("Template", value: backend.template.capitalized)
                            LabeledContent("Revision", value: String(backend.revision))
                            LabeledContent("Public reads", value: backend.publishRead ? "Enabled" : "Off")
                        }
                        Button("Refresh details") { run { backend = try await HTMLAppBackendAPI.status(link) } }
                    }
                    Section("Keys") {
                        Text("Public read key").font(.caption).foregroundStyle(.secondary)
                        Text(link.readKey).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        Button("Copy public read key") { UIPasteboard.general.string = link.readKey }
                        if !link.managementKey.isEmpty {
                        if showKey {
                            Text(link.managementKey).font(.system(.footnote, design: .monospaced))
                                .privacySensitive()
                            Button("Copy private key") { copyPrivate(link.managementKey) }
                            Button("Hide private key") { showKey = false }
                        } else {
                            Button("View private management key") {
                                run {
                                    let auth = LAContext()
                                    guard try await auth.evaluatePolicy(.deviceOwnerAuthentication,
                                                                        localizedReason: "Reveal this app’s backend management key.") else { return }
                                    guard scenePhase == .active else { return }
                                    showKey = true
                                }
                            }
                        }
                        }
                        Text("The management key can change or delete this backend. HTMLApp keeps it out of HTML, Forge prompts and transfers.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if backend?.template == "notification" {
                        Section("Notifications") {
                            LabeledContent("APNs on VPS", value: backend?.pushConfigured == true ? "Configured" : "Not configured")
                            LabeledContent("Phone", value: backend?.deviceRegistered == true ? "Registered" : "Not registered")
                            Button("Register this phone") {
                                run {
                                    let token: String = try await withCheckedThrowingContinuation { continuation in
                                        HTMLAppRemotePushService.shared.register { result in
                                            continuation.resume(with: result)
                                        }
                                    }
                                    _ = try await HTMLAppBackendAPI.request(link, path: "/device", method: "PUT",
                                                                           key: link.managementKey, body: ["deviceToken": token])
                                    backend = try await HTMLAppBackendAPI.status(link)
                                    message = "This phone is registered."
                                }
                            }
                            Button("Send test notification") {
                                run {
                                    _ = try await HTMLAppBackendAPI.send(link, title: "HTMLApp", body: "Your backend sent a test notification.")
                                    message = "Apple accepted the test notification for delivery."
                                }
                            }
                            .disabled(backend?.deviceRegistered != true || backend?.pushConfigured != true || link.sendKey == nil)
                            if let key = link.sendKey {
                                Button("Copy notification URL") { UIPasteboard.general.string = HTMLAppBackendAPI.url(link, path: "/notify").absoluteString }
                                Button("Copy send-only key") { copyPrivate(key) }
                            }
                        }
                    }
                    if link.sdkVersion != 2 {
                    Section("Stored data") {
                        Button("Edit JSON data") {
                            run {
                                let result = try await HTMLAppBackendAPI.request(link, path: "/data", method: "GET", key: link.managementKey)
                                guard let value = result["data"] else { throw HTMLAppBackendError(message: "No JSON data returned.") }
                                let bytes = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .fragmentsAllowed])
                                dataDraft = String(decoding: bytes, as: UTF8.self)
                                dataEditor = true
                            }
                        }
                        if let backend {
                            Toggle("Allow reads with the public key", isOn: Binding(
                                get: { self.backend?.publishRead ?? false },
                                set: { publish in
                                    run {
                                        _ = try await HTMLAppBackendAPI.request(link, path: "/deploy", method: "POST",
                                            key: link.managementKey,
                                            body: ["baseRevision": backend.revision, "name": backend.name, "publishRead": publish])
                                        self.backend = try await HTMLAppBackendAPI.status(link)
                                    }
                                }))
                        }
                        Text("Anyone with the read key can read this entire document when public reads are enabled.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    }
                    Section("Backend script") {
                        if link.sdkVersion == 2 && !link.managementKey.isEmpty {
                            Button("Download deployed script") {
                                run {
                                    let result = try await HTMLAppBackendAPI.raw("/v2/manage/apps/" + link.appID + "/source", method: "GET", key: link.managementKey)
                                    guard let text = result["source"] as? String else { throw HTMLAppBackendError(message: "No source returned.") }
                                    let url = try HTMLAppBackendStore.sourceURL(for: app.id)
                                    try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
                                    source = text
                                    shareURL = url
                                }
                            }
                        }
                        if source != nil {
                            Button("View script") { showSource = true }
                            if let shareURL {
                                ShareLink(item: shareURL) { Label("Share script file", systemImage: "square.and.arrow.up") }
                            }
                        }
                        Button(source == nil ? "Attach local Python script" : "Replace local Python script") { importing = true }
                        Text(link.sdkVersion == 2 ? "Your generated Python runs in an isolated server. Review the source for secrets before exporting." : "Legacy templates have no executable per-app source.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section {
                        Button("Unlink from this app", role: .destructive) { confirmUnlink = true }
                    }
                } else {
                    Section("Connect a backend") {
                        if let status = HTMLAppBackendProvisioning.status(for: app.id) {
                            Text(status)
                            Button("Retry automatic setup") {
                                run {
                                    await HTMLAppBackendProvisioning.flush()
                                    link = HTMLAppBackendStore.link(for: app.id)
                                    if let link { backend = try await HTMLAppBackendAPI.status(link) }
                                    else { message = HTMLAppBackendProvisioning.status(for: app.id) }
                                }
                            }
                        }
                        if app.html.contains("htmlapp-backend-v2") {
                            Text(HTMLAppBackendProvisioning.isPaired ? "This app includes server code. Connect it using your saved secret." : "Enter your secret once in Settings → AI & Voice → Automatic backends.")
                            Button("Connect automatically") {
                                run { try await connectRuntime() }
                            }.disabled(!HTMLAppBackendProvisioning.isPaired)
                        } else if HTMLAppBackendProvisioning.template(in: app.html) != nil {
                            Text("This app uses a legacy backend. Automatic setup uses your saved secret.")
                        } else {
                            Text("This app has no deployable backend code. Your saved VPS secret does not need to be entered again.")
                            Button("Repair backend with Forge") { repairingBackend = true }
                        }
                        DisclosureGroup("Advanced: link a legacy backend") {
                            SecureField("Provisioning JSON", text: $provisioning)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Verify and link") { linkBackend() }
                                .disabled(provisioning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                if busy { ProgressView() }
                if let message { Section { Text(message).font(.footnote) } }
            }
            .navigationTitle("Backend")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "py") ?? .plainText]) { result in
                do { try importSource(result.get()) }
                catch { message = error.localizedDescription }
            }
            .sheet(isPresented: $repairingBackend) {
                AIGenerationView(existingApp: app, initialEdit: "Implement this app’s complete intended backend and connect every server-dependent control. Replace placeholder URLs and local-only substitutes with a generated runtime v2 Python bundle and matching frontend. Preserve the design and user data. Use the saved VPS secret automatically; do not ask for provisioning JSON.")
                    .environmentObject(store)
                    .interactiveDismissDisabled(true)
            }
            .sheet(isPresented: $dataEditor) {
                NavigationStack {
                    VStack {
                        TextEditor(text: $dataDraft)
                            .font(.system(.footnote, design: .monospaced))
                            .autocorrectionDisabled()
                        if let message { Text(message).font(.footnote) }
                        if busy { ProgressView() }
                    }
                    .padding()
                    .navigationTitle("Backend JSON")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dataEditor = false }.disabled(busy)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                guard let link else { return }
                                run {
                                    guard dataDraft.utf8.count <= 2_000_000,
                                          let value = try? JSONSerialization.jsonObject(with: Data(dataDraft.utf8), options: [.fragmentsAllowed]) else {
                                        throw HTMLAppBackendError(message: "Enter valid JSON under 2 MB.")
                                    }
                                    _ = try await HTMLAppBackendAPI.request(link, path: "/data", method: "PUT",
                                                                           key: link.managementKey, body: ["data": value])
                                    dataEditor = false
                                    message = "Backend data saved."
                                }
                            }.disabled(busy)
                        }
                    }
                    .interactiveDismissDisabled(busy)
                }
            }
            .sheet(isPresented: $showSource) {
                NavigationStack {
                    ScrollView {
                        Text(source ?? "").font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled).padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .navigationTitle("Backend script")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showSource = false } } }
                }
            }
            .confirmationDialog("Unlink this app?", isPresented: $confirmUnlink, titleVisibility: .visible) {
                Button("Unlink", role: .destructive) {
                    HTMLAppBackendStore.unlink(app.id)
                    link = nil
                    backend = nil
                    source = nil
                    shareURL = nil
                    showKey = false
                }
            } message: {
                Text("This removes the local link and script. The VPS backend keeps running.")
            }
            .onReceive(NotificationCenter.default.publisher(for: HTMLAppBackendProvisioning.didFinish)) { _ in
                link = HTMLAppBackendStore.link(for: app.id)
                message = link == nil ? HTMLAppBackendProvisioning.status(for: app.id) : nil
                if let link { run { backend = try await HTMLAppBackendAPI.status(link) } }
            }
            .onChange(of: scenePhase) { if $0 != .active { showKey = false } }
            .disabled(busy)
        }
        .task {
            link = HTMLAppBackendStore.link(for: app.id)
            if let url = try? HTMLAppBackendStore.sourceURL(for: app.id),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                source = text
                shareURL = url
            }
            // Opening this native panel explicitly requests setup for an
            // existing app, including an imported or transferred copy.
            if link == nil, let template = HTMLAppBackendProvisioning.template(in: app.html) {
                HTMLAppBackendProvisioning.enqueue(app, template: template)
            }
            run {
                if link == nil, app.html.contains("htmlapp-backend-v2"), HTMLAppBackendProvisioning.isPaired {
                    try await connectRuntime()
                }
                await HTMLAppBackendProvisioning.flush()
                link = HTMLAppBackendStore.link(for: app.id)
                if let link { backend = try await HTMLAppBackendAPI.status(link) }
                else { message = HTMLAppBackendProvisioning.status(for: app.id) }
            }
        }
    }

    private func connectRuntime() async throws {
        let issues = ForgeBackendContract.issues(request: app.summary, html: app.html)
        guard issues.isEmpty else { throw HTMLAppBackendError(message: issues.joined(separator: " ")) }
        guard let bundle = try HTMLAppRuntimeBundle.extract(app.html) else { throw HTMLAppBackendError(message: "Missing generated server code. Ask Forge to repair this app.") }
        try await HTMLAppRuntimeBackend.deploy(localID: app.id, name: app.name, bundle: bundle)
        link = HTMLAppBackendStore.link(for: app.id)
        if let link { backend = try await HTMLAppBackendAPI.status(link) }
        let url = try HTMLAppBackendStore.sourceURL(for: app.id)
        source = try String(contentsOf: url, encoding: .utf8)
        shareURL = url
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        message = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() }
            catch { message = error.localizedDescription }
        }
    }

    private func linkBackend() {
        run {
            guard provisioning.utf8.count < 4096,
                  let candidate = try? JSONDecoder().decode(HTMLAppBackendLink.self, from: Data(provisioning.utf8)),
                  candidate.isValid else { throw HTMLAppBackendError(message: "Paste the complete provisioning JSON from your VPS.") }
            guard !HTMLAppBackendDeletionQueue.isQueued(app.id),
                  !HTMLAppBackendDeletionQueue.containsBackend(candidate.appID),
                  !store.apps.contains(where: { $0.id != app.id && HTMLAppBackendStore.link(for: $0.id)?.appID == candidate.appID }) else {
                throw HTMLAppBackendError(message: "This backend is already linked or a deletion is pending.")
            }
            let details = try await HTMLAppBackendAPI.status(candidate)
            try HTMLAppBackendStore.save(candidate, for: app.id)
            backend = details
            link = candidate
            provisioning = ""
        }
    }

    private func copyPrivate(_ value: String) {
        UIPasteboard.general.setItems([["public.utf8-plain-text": value]],
                                     options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
    }

    private func importSource(_ url: URL) throws {
        let allowed = url.startAccessingSecurityScopedResource()
        defer { if allowed { url.stopAccessingSecurityScopedResource() } }
        guard url.pathExtension.lowercased() == "py",
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000 else {
            throw HTMLAppBackendError(message: "Choose a Python file under 2 MB.")
        }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 2_000_000, let text = String(data: bytes, encoding: .utf8) else {
            throw HTMLAppBackendError(message: "Choose a UTF-8 Python file under 2 MB.")
        }
        let destination = try HTMLAppBackendStore.sourceURL(for: app.id)
        try bytes.write(to: destination, options: [.atomic, .completeFileProtection])
        source = text
        shareURL = destination
    }
}


// Pairing opts saved apps into automatic setup. Each local app gets its own
// credentials, including imported and transferred copies.
@MainActor
enum HTMLAppBackendProvisioning {
    private struct Pending: Codable {
        var name: String
        var template: String
        var clientID = UUID().uuidString
        var attempted = false
        var deleted = false
        var error: String?
    }

    private static let account = "backend-provision-key"
    private static let queue = "htmlapp.backend.pendingProvision"
    private static var runningTask: Task<Void, Never>?
    static let didFinish = Notification.Name("HTMLAppBackendProvisioningDidFinish")
    static var isPaired: Bool { KeychainValueStore.read(account: account) != nil }

    static func template(in html: String) -> String? {
        let source = String(html.prefix(32_000))
        let pattern = #"<meta\s+name\s*=\s*["']htmlapp-backend["']\s+content\s*=\s*["'](document|notification)["']\s*/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range(at: 1), in: source) else { return nil }
        let value = source[range].lowercased()
        let operation = value == "notification" ? "notify" : "read"
        return html.contains(".backend." + operation) || html.contains(".backend?." + operation) ? value : nil
    }

    private static var jobs: [String: Pending] {
        get {
            guard let data = UserDefaults.standard.data(forKey: queue) else { return [:] }
            return (try? JSONDecoder().decode([String: Pending].self, from: data)) ?? [:]
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: queue) }
    }

    static func pair(_ key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count == 64, trimmed.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw HTMLAppBackendError(message: "Paste the 64-character provisioning key from your VPS.")
        }
        try await HTMLAppBackendAPI.pair(trimmed)
        KeychainValueStore.write(trimmed, account: account)
        guard KeychainValueStore.read(account: account) == trimmed else {
            throw HTMLAppBackendError(message: "The device could not save the pairing key.")
        }
        await flush()
    }

    static func status(for appID: String) -> String? {
        guard let job = jobs[appID] else { return nil }
        return job.error ?? (isPaired ? "Waiting for automatic backend setup." : "Pair your VPS once in Settings to finish setup.")
    }

    static func enqueue(_ app: SavedHTMLApp, template: String, startImmediately: Bool = true) {
        guard HTMLAppBackendStore.link(for: app.id) == nil, jobs[app.id] == nil else { return }
        jobs[app.id] = Pending(name: String(app.name.prefix(40)), template: template)
        if startImmediately { Task { await flush() } }
    }

    static func cancel(_ appID: String) {
        guard var job = jobs[appID] else { return }
        if job.attempted {
            job.deleted = true
            jobs[appID] = job
        } else {
            jobs.removeValue(forKey: appID)
        }
    }

    static func flush() async {
        if let runningTask {
            await runningTask.value
            return
        }
        guard let key = KeychainValueStore.read(account: account) else { return }
        let task = Task { await processPending(key: key) }
        runningTask = task
        await task.value
        runningTask = nil
        NotificationCenter.default.post(name: didFinish, object: nil)
    }

    private static func processPending(key: String) async {
        // Include jobs added while a request is in flight, and attempt failures
        // only once per pass so a network error cannot create a retry loop.
        var attempted = Set<String>()
        while let appID = jobs.keys.sorted().first(where: { !attempted.contains($0) }) {
            attempted.insert(appID)
            guard var job = jobs[appID] else { continue }
            if HTMLAppBackendStore.link(for: appID) != nil {
                if job.deleted { HTMLAppBackendDeletionQueue.enqueue(appID) }
                jobs.removeValue(forKey: appID)
                continue
            }
            job.attempted = true
            jobs[appID] = job
            do {
                let link = try await HTMLAppBackendAPI.provision(clientID: job.clientID, name: job.name, template: job.template, key: key)
                try HTMLAppBackendStore.save(link, for: appID)
                if jobs[appID]?.deleted == true {
                    HTMLAppBackendDeletionQueue.enqueue(appID)
                } else if job.template == "notification" && UIApplication.shared.applicationState == .active {
                    // Registration can still require the user's iOS consent.
                    // A push failure must not roll back an otherwise valid link.
                    try? await registerPhoneIfReady(link)
                }
                jobs.removeValue(forKey: appID)
            } catch {
                if (error as? HTMLAppBackendError)?.status == 410 && jobs[appID]?.deleted == true {
                    jobs.removeValue(forKey: appID)
                } else {
                    jobs[appID]?.error = error.localizedDescription
                }
            }
        }
    }
    static func registerPhoneIfReady(_ link: HTMLAppBackendLink) async throws {
        let details = try await HTMLAppBackendAPI.status(link)
        guard details.pushConfigured, !details.deviceRegistered else { return }
        let token: String = try await withCheckedThrowingContinuation { continuation in
            HTMLAppRemotePushService.shared.register { continuation.resume(with: $0) }
        }
        _ = try await HTMLAppBackendAPI.request(link, path: "/device", method: "PUT",
                                               key: link.managementKey, body: ["deviceToken": token])
    }

}

@MainActor
struct HTMLAppBackendPairingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var key = ""
    @State private var busy = false
    @State private var paired = HTMLAppBackendProvisioning.isPaired
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text(paired ? "Connected. Apps that need a backend connect automatically."
                     : "Enter your secret once. HTMLApp handles backend setup for your apps.")
                SecureField("Secret", text: $key)
                    .disabled(busy)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { connect() }
                    .onChange(of: key) { value in
                        let secret = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if secret.utf8.count == 64 { connect() }
                    }
                Button(paired ? "Update secret" : "Connect") { connect() }
                .disabled(busy || key.isEmpty)
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Automatic backends")
    }

    private func connect() {
        guard !busy, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let secret = key
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await HTMLAppBackendProvisioning.pair(secret)
                paired = true
                key = ""
                store.prepareAutomaticBackends()
                await HTMLAppBackendProvisioning.flush()
            } catch { self.error = error.localizedDescription }
        }
    }
}
