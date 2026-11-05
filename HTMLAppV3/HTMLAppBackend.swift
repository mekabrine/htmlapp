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

    var isValid: Bool {
        appID.range(of: #"^[A-Z2-7]{12}$"#, options: .regularExpression) != nil
            && Self.isKey(managementKey, length: 20)
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
        guard HTMLAppBackendStore.link(for: appID) != nil else { return }
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
                let result = try await HTMLAppBackendAPI.request(link, path: "", method: "DELETE", key: link.managementKey)
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

    static func pair(_ key: String) async throws {
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

    private static func authenticatedRequest(_ url: URL, method: String, key: String,
                                             body: [String: Any]?) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
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

    static func status(_ link: HTMLAppBackendLink) async throws -> HTMLAppBackendStatus {
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

    var body: some View {
        NavigationStack {
            Form {
                if let link {
                    Section("Backend details") {
                        LabeledContent("Backend ID", value: link.appID)
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
                    Section("Backend script") {
                        if source != nil {
                            Button("View script") { showSource = true }
                            if let shareURL {
                                ShareLink(item: shareURL) { Label("Share script file", systemImage: "square.and.arrow.up") }
                            }
                        }
                        Button(source == nil ? "Attach local Python script" : "Replace local Python script") { importing = true }
                        Text("Approved gateway templates have no per-app Python file. An attached script is a local reference only. Sharing it is a separate action, so remove any secrets first.")
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
                        Text("For new apps, pair your VPS in Settings → AI & Voice → Automatic backends. You can also link an existing backend using its provisioning JSON.")
                        SecureField("Provisioning JSON", text: $provisioning)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Verify and link") { linkBackend() }
                            .disabled(provisioning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            if let link { run { backend = try await HTMLAppBackendAPI.status(link) } }
        }
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


// Only Forge saves opt into provisioning. Imported and Nearby copies cannot
// trigger provisioning by including a marker in their HTML.
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
    private static var running = false
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

    static func enqueue(_ app: SavedHTMLApp, template: String) {
        guard HTMLAppBackendStore.link(for: app.id) == nil, jobs[app.id] == nil else { return }
        jobs[app.id] = Pending(name: String(app.name.prefix(40)), template: template)
        Task { await flush() }
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
        guard !running, let key = KeychainValueStore.read(account: account) else { return }
        running = true
        defer { running = false }
        for appID in jobs.keys.sorted() {
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
    private static func registerPhoneIfReady(_ link: HTMLAppBackendLink) async throws {
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
    @State private var key = ""
    @State private var busy = false
    @State private var paired = HTMLAppBackendProvisioning.isPaired
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text(paired ? "VPS paired. Forge apps can set up their backends when saved."
                     : "Pair this device once. Forge apps that need a backend will link automatically when saved.")
                SecureField("VPS provisioning key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(paired ? "Update pairing" : "Pair with VPS") {
                    busy = true
                    error = nil
                    Task { @MainActor in
                        defer { busy = false }
                        do {
                            try await HTMLAppBackendProvisioning.pair(key)
                            paired = true
                            key = ""
                        } catch { self.error = error.localizedDescription }
                    }
                }
                .disabled(busy || key.isEmpty)
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Automatic backends")
    }
}
