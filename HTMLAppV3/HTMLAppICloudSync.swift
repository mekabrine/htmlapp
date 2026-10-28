import Foundation

/// Optional iCloud Documents mirroring. Local Library and portable data remain
/// authoritative while iCloud is disabled or unavailable.
enum HTMLAppICloudPreferences {
    static let appsKey = "htmlapp.icloud.syncApps"
    static let dataKey = "htmlapp.icloud.syncData"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: appsKey) }
    static var includeData: Bool { enabled && UserDefaults.standard.bool(forKey: dataKey) }
    private static let deletedKey = "htmlapp.icloud.deleted"
    static var deleted: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: deletedKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: deletedKey) }
    }
    static func markDeleted(_ id: String) {
        var items = deleted
        items[id] = Date().timeIntervalSince1970
        deleted = items
    }
}

actor HTMLAppICloudSync {
    static let shared = HTMLAppICloudSync()
    private let fm = FileManager.default
    private var syncing = false

    struct Incoming: Sendable {
        var apps: [SavedHTMLApp] = []
        var folders: [LibraryFolder] = []
        var data: [String: [String: String]] = [:]
        var deleted: [String: Double] = [:]
        var pendingDownloads = 0
        var sourceConflicts: Set<String> = []
        var dataConflicts: Set<String> = []
    }

    /// FileManager's ubiquity lookup can block: never call on the main actor.
    private func folder() throws -> URL {
        guard let container = fm.url(forUbiquityContainerIdentifier: nil) else { throw HTMLAppSyncError.unavailable }
        let folder = container.appendingPathComponent("Documents/HTMLAppSync", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func read(_ url: URL) -> Data? {
        if fm.isUbiquitousItem(at: url) { try? fm.startDownloadingUbiquitousItem(at: url) }
        var result: Data?
        var error: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: [], error: &error) { coordinated in
            result = try? Data(contentsOf: coordinated)
        }
        return result
    }

    private func write(_ data: Data, at url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinated in
            do { try data.write(to: coordinated, options: .atomic) }
            catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    static func sourceValues(_ app: SavedHTMLApp) -> [String: String] {
        ["html": app.html, "summary": app.summary, "icon": app.favicon?.base64EncodedString() ?? ""]
    }

    private func reviewSnapshot(at url: URL, replacement: Data?, matches: @escaping (Data) -> Bool) throws {
        if fm.isUbiquitousItem(at: url) { try fm.startDownloadingUbiquitousItem(at: url) }
        var coordinationError: NSError?
        var operationError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinated in
            do {
                let current = try Data(contentsOf: coordinated)
                guard matches(current) else { throw HTMLAppSyncError.changedDuringReview }
                if let replacement { try replacement.write(to: coordinated, options: .atomic) }
            } catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }

    /// Check and replace under one file-coordination lock per document. iCloud
    /// remains eventually consistent; this is not a cross-document transaction.
    func resolveConflict(_ conflict: HTMLAppSyncConflict, replacementApp: SavedHTMLApp?, replacementData: [String: String]?) throws {
        guard HTMLAppICloudPreferences.enabled else { throw HTMLAppSyncError.disabled }
        let root = try folder()
        if let expected = conflict.cloudApp {
            let url = root.appendingPathComponent("Apps").appendingPathComponent(expected.id + ".json")
            let bytes = try replacementApp.map { try JSONEncoder().encode($0) }
            try reviewSnapshot(at: url, replacement: bytes) { data in
                guard let current = try? JSONDecoder().decode(SavedHTMLApp.self, from: data) else { return false }
                return Self.sourceValues(current) == Self.sourceValues(expected)
            }
            if let replacementApp {
                HTMLAppSyncMergePolicy.acknowledge(Self.sourceValues(replacementApp), id: replacementApp.id, kind: "source")
            }
        }
        if let expected = conflict.cloudData {
            guard HTMLAppICloudPreferences.includeData else { throw HTMLAppSyncError.disabled }
            let url = root.appendingPathComponent("Data").appendingPathComponent(conflict.id + ".json")
            let bytes = try replacementData.map { try JSONEncoder().encode($0) }
            try reviewSnapshot(at: url, replacement: bytes) { data in
                (try? JSONDecoder().decode([String: String].self, from: data)) == expected
            }
            if let replacementData {
                HTMLAppSyncMergePolicy.acknowledge(replacementData, id: conflict.id, kind: "data")
            }
        }
    }

    func exchange(localApps: [SavedHTMLApp], localFolders: [LibraryFolder], localData: [String: [String: String]], localDeleted: [String: Double]) throws -> Incoming {
        guard HTMLAppICloudPreferences.enabled, !syncing else { return Incoming() }
        let root = try folder()
        syncing = true
        defer { syncing = false }
        let appRoot = root.appendingPathComponent("Apps", isDirectory: true)
        let dataRoot = root.appendingPathComponent("Data", isDirectory: true)
        try fm.createDirectory(at: appRoot, withIntermediateDirectories: true)
        if HTMLAppICloudPreferences.includeData {
            try fm.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        var incoming = Incoming()
        var deletions = localDeleted
        let deleteRoot = root.appendingPathComponent("Deleted", isDirectory: true)
        try fm.createDirectory(at: deleteRoot, withIntermediateDirectories: true)
        for url in try fm.contentsOfDirectory(at: deleteRoot, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
            if let bytes = read(url), let time = try? JSONDecoder().decode(Double.self, from: bytes) {
                let id = url.deletingPathExtension().lastPathComponent
                deletions[id] = max(deletions[id] ?? 0, time)
            } else { incoming.pendingDownloads += 1 }
        }
        for (id, time) in deletions where (localDeleted[id] ?? 0) >= time {
            if let bytes = try? encoder.encode(time) {
                try write(bytes, at: deleteRoot.appendingPathComponent(id + ".json"))
            }
        }
        incoming.deleted = deletions
        let foldersURL = root.appendingPathComponent("folders.json")
        let folderFileExists = fm.fileExists(atPath: foldersURL.path)
        let remoteFolderBytes = folderFileExists ? read(foldersURL) : nil
        let remoteFolders = remoteFolderBytes.flatMap {
            try? JSONDecoder().decode([LibraryFolder].self, from: $0)
        }
        if folderFileExists && remoteFolders == nil { incoming.pendingDownloads += 1 }
        if let remoteFolders {
            incoming.folders = remoteFolders.filter { cloud in
                !localFolders.contains(where: { $0.id == cloud.id })
            }
        }
        // Do not replace a cloud folder index that has not finished downloading.
        if !folderFileExists || remoteFolders != nil {
            var mergedFolders = localFolders
            mergedFolders.append(contentsOf: incoming.folders)
            if let bytes = try? encoder.encode(mergedFolders) { try write(bytes, at: foldersURL) }
        }
        var remote: [String: SavedHTMLApp] = [:]
        var unreadableRemoteIDs = Set<String>()
        for url in try fm.contentsOfDirectory(at: appRoot, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
            if let bytes = read(url), let app = try? JSONDecoder().decode(SavedHTMLApp.self, from: bytes) {
                remote[app.id] = app
            } else {
                // An iCloud file placeholder is not proof that the remote file
                // is absent. Never overwrite it while download is pending.
                unreadableRemoteIDs.insert(url.deletingPathExtension().lastPathComponent)
                incoming.pendingDownloads += 1
            }
        }
        for app in localApps {
            if (deletions[app.id] ?? 0) > app.updatedAt.timeIntervalSince1970 { continue }
            let values = Self.sourceValues(app)
            if let cloud = remote.removeValue(forKey: app.id) {
                switch HTMLAppSyncMergePolicy.decide(local: values, cloud: Self.sourceValues(cloud),
                    baseline: HTMLAppSyncMergePolicy.baseline(id: app.id, kind: "source")) {
                case .conflict:
                    incoming.sourceConflicts.insert(app.id)
                    incoming.apps.append(cloud)
                case .download:
                    incoming.apps.append(cloud)
                case .equal:
                    HTMLAppSyncMergePolicy.acknowledge(values, id: app.id, kind: "source")
                    // Source is identical; retain the existing metadata policy.
                    if cloud.updatedAt > app.updatedAt { incoming.apps.append(cloud) }
                    else { try write(encoder.encode(app), at: appRoot.appendingPathComponent(app.id + ".json")) }
                case .upload:
                    try write(encoder.encode(app), at: appRoot.appendingPathComponent(app.id + ".json"))
                    HTMLAppSyncMergePolicy.acknowledge(values, id: app.id, kind: "source")
                }
            } else if !unreadableRemoteIDs.contains(app.id) {
                try write(encoder.encode(app), at: appRoot.appendingPathComponent(app.id + ".json"))
                HTMLAppSyncMergePolicy.acknowledge(values, id: app.id, kind: "source")
            }
        }
        incoming.apps.append(contentsOf: remote.values.filter { (deletions[$0.id] ?? 0) <= $0.updatedAt.timeIntervalSince1970 })

        if HTMLAppICloudPreferences.includeData {
            // Preserve per-app data independently and never mirror permissions,
            // tokens, app-specific Keychain items, or OS authorization decisions.
            let ids = Set(localApps.map(\.id)).union(incoming.apps.map(\.id)).filter { deletions[$0] == nil }
            for id in ids {
                let url = dataRoot.appendingPathComponent(id + ".json")
                let values = localData[id] ?? [:]
                let localURL = HTMLAppPortableDataStore.fileURL(appID: id)
                let cloudExists = fm.fileExists(atPath: url.path)
                if cloudExists {
                    guard let bytes = read(url),
                          let decoded = try? JSONDecoder().decode([String: String].self, from: bytes) else {
                        incoming.pendingDownloads += 1
                        continue
                    }
                    if !fm.fileExists(atPath: localURL.path) {
                        incoming.data[id] = decoded
                    } else {
                        switch HTMLAppSyncMergePolicy.decide(local: values, cloud: decoded,
                            baseline: HTMLAppSyncMergePolicy.baseline(id: id, kind: "data")) {
                        case .equal:
                            HTMLAppSyncMergePolicy.acknowledge(values, id: id, kind: "data")
                        case .upload:
                            try write(encoder.encode(values), at: url)
                            HTMLAppSyncMergePolicy.acknowledge(values, id: id, kind: "data")
                        case .download:
                            incoming.data[id] = decoded
                        case .conflict:
                            incoming.dataConflicts.insert(id)
                            incoming.data[id] = decoded
                        }
                    }
                } else if fm.fileExists(atPath: localURL.path), let bytes = try? encoder.encode(values) {
                    // Explicit empty local snapshots must overwrite old cloud values.
                    // A missing local file does not mean the user cleared data.
                    try write(bytes, at: url)
                    HTMLAppSyncMergePolicy.acknowledge(values, id: id, kind: "data")
                }
            }
        }
        return incoming
    }
}
