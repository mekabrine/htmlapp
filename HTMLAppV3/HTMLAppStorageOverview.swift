import Foundation
import SwiftUI

struct HTMLAppStorageOverview: View {
    let apps: [SavedHTMLApp]
    @State private var report: HTMLAppStorageReport?
    @State private var scanRevision = 0
    @State private var scanning = true

    var body: some View {
        List {
            if let report {
                Section {
                    if report.measuredFileCount == 0 {
                        Text("HTMLApp could not measure any files. Try refreshing with the device unlocked.")
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Total measured", value: size(report.dataBytes + report.bundleBytes))
                        LabeledContent("App data and files", value: size(report.dataBytes))
                        LabeledContent("Installed app and extensions", value: size(report.bundleBytes))
                    }
                    if report.unreadableCount > 0 {
                        Text("Some files or folders could not be read. The totals may be incomplete.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Uses allocated file sizes where available and file lengths otherwise. iOS may report a different total.")
                }

                Section("Whisper Offline") {
                    if let whisper = report.whisper {
                        breakdown([whisper])
                    } else {
                        Text(report.unreadableCount > 0 || report.measuredFileCount == 0
                             ? "Model size unavailable"
                             : "No Whisper model files found")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(report.apps) { app in
                        DisclosureGroup {
                            if app.categories.isEmpty { Text("No separate files found").foregroundStyle(.secondary) }
                            breakdown(app.categories)
                        } label: {
                            sizeRow(app.name, app.bytes)
                        }
                    }
                    if report.apps.isEmpty { Text("No saved apps") }
                } header: {
                    Text("Saved Apps")
                } footer: {
                    Text("Largest first. Library entry sizes are estimated from each app’s share of the library file. Shared WebKit data appears below.")
                }

                Section {
                    LabeledContent("Measured size", value: size(report.gpu?.bytes ?? 0))
                    LabeledContent("Cache folders", value: report.gpuFolderCount.formatted())
                    if let last = UserDefaults.standard.dictionary(forKey: HTMLAppGPUCache.resultKey),
                       let date = last["date"] as? Date {
                        LabeledContent("Last cleanup", value: date.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Space reclaimed", value: size((last["bytes"] as? NSNumber)?.int64Value ?? 0))
                        if let failed = last["failed"] as? Int, failed > 0 {
                            Text("\(failed) folders could not be removed.").foregroundStyle(.secondary)
                        }
                    }
                    if let gpu = report.gpu { breakdown(gpu.children) }
                } header: {
                    Text("GPU Temporary Files")
                } footer: {
                    Text("At startup, HTMLApp removes the oldest 10 eligible folders when there are at least 20. Files still in use or with an unfamiliar layout are left alone.")
                }

                Section("Shared Data and Other Files") {
                    breakdown(report.shared)
                    if report.shared.isEmpty { Text("No shared files found") }
                }

                Section("Installed App Files") {
                    breakdown(report.bundle)
                }
            }
            if scanning {
                ProgressView("Measuring storage…")
            }
        }
        .navigationTitle("Storage")
        .toolbar {
            Button {
                scanRevision += 1
            } label: {
                Label("Refresh Storage", systemImage: "arrow.clockwise")
            }
            .disabled(scanning)
        }
        .task(id: scanRevision) {
            scanning = true
            await HTMLAppGPUCache.maintenance.value
            guard !Task.isCancelled else { return }
            let snapshot = apps
            let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            let bundle = Bundle.main.bundleURL
            let group = HTMLAppSharedContainer.directory
            let scan = Task.detached(priority: .utility) {
                HTMLAppStorageReport.measure(apps: snapshot, home: home, bundle: bundle, group: group)
            }
            let result = await withTaskCancellationHandler {
                await scan.value
            } onCancel: {
                scan.cancel()
            }
            guard !Task.isCancelled else { return }
            report = result
            scanning = false
        }
    }

    private func breakdown(_ nodes: [HTMLAppStorageReport.Node]) -> some View {
        OutlineGroup(nodes, children: \.branch) { node in
            sizeRow(node.name, node.bytes)
        }
    }

    private func sizeRow(_ title: String, _ bytes: Int64) -> some View {
        LabeledContent {
            Text(size(bytes)).monospacedDigit()
        } label: {
            Text(title).lineLimit(2)
        }
    }

    private func size(_ bytes: Int64) -> String {
        bytes == 0 ? "0 bytes" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct HTMLAppStorageReport: Sendable {
    struct Node: Identifiable, Sendable {
        let id: String
        let name: String
        let bytes: Int64
        let children: [Node]
        var branch: [Node]? { children.isEmpty ? nil : children }
    }

    struct App: Identifiable, Sendable {
        let id: String
        let name: String
        let categories: [Node]
        var bytes: Int64 { categories.reduce(0) { $0 + $1.bytes } }
    }

    let apps: [App]
    let shared: [Node]
    let whisper: Node?
    let gpu: Node?
    let gpuFolderCount: Int
    let bundle: [Node]
    let unreadableCount: Int
    let measuredFileCount: Int
    var dataBytes: Int64 {
        apps.reduce(0) { $0 + $1.bytes } + shared.reduce(0) { $0 + $1.bytes } + (whisper?.bytes ?? 0) + (gpu?.bytes ?? 0)
    }
    var bundleBytes: Int64 { bundle.reduce(0) { $0 + $1.bytes } }

    /// An accumulator local to the scan. Each measured file belongs to one branch.
    private final class Folder {
        var bytes: Int64 = 0
        var children: [String: Folder] = [:]

        func add(_ bytes: Int64, path: ArraySlice<String>) {
            self.bytes += bytes
            guard let name = path.first else { return }
            let folder = children[name] ?? Folder()
            children[name] = folder
            folder.add(bytes, path: path.dropFirst())
        }

        func nodes(prefix: String = "") -> [Node] {
            children.map { name, folder in
                let id = prefix + "/" + name
                return Node(id: id, name: name, bytes: folder.bytes, children: folder.nodes(prefix: id))
            }.sorted { lhs, rhs in
                lhs.bytes == rhs.bytes ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending : lhs.bytes > rhs.bytes
            }
        }
    }

    static func measure(apps: [SavedHTMLApp], home: URL, bundle: URL, group: URL?) -> Self {
        let shared = Folder()
        let installed = Folder()
        let gpuFiles = Folder()
        let appFolders = apps.reduce(into: [String: Folder]()) { $0[$1.id] = Folder() }
        let safeIDs = Dictionary(grouping: apps.map(\.id), by: { id in
            id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        })
        let asciiIDs = Dictionary(grouping: apps.map(\.id), by: { id in
            id.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        })
        var libraryBytes: Int64 = 0
        var unreadable = 0
        var measuredFiles = 0
        var scannedRoots: [[String]] = []

        func scan(_ directory: URL, record: (Int64, [String]) -> Void) {
            let identity = directory.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            guard !scannedRoots.contains(where: { identity.starts(with: $0) }) else { return }
            scannedRoots.append(identity)

            let manager = FileManager.default
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey
            ]
            // Build relative paths during traversal. Foundation can spell the same
            // sandbox path differently in a directory URL and its child URLs.
            var pending: [(url: URL, path: [String])] = [(directory, [])]
            while let folder = pending.popLast() {
                if Task.isCancelled { return }
                let files: [URL]
                do {
                    files = try manager.contentsOfDirectory(at: folder.url,
                        includingPropertiesForKeys: Array(keys), options: [])
                } catch {
                    unreadable += 1
                    continue
                }
                for file in files {
                    if Task.isCancelled { return }
                    do {
                        let values = try file.resourceValues(forKeys: keys)
                        guard values.isSymbolicLink != true else { continue }
                        let path = folder.path + [file.lastPathComponent]
                        if values.isDirectory == true {
                            pending.append((file, path))
                        } else if values.isRegularFile == true {
                            let allocated = max(values.totalFileAllocatedSize ?? 0, values.fileAllocatedSize ?? 0)
                            let bytes: Int64
                            if allocated > 0 {
                                bytes = Int64(allocated)
                            } else if let length = values.fileSize, length > 0 {
                                bytes = Int64(length)
                            } else {
                                let attributes = try manager.attributesOfItem(atPath: file.path)
                                guard let length = attributes[.size] as? NSNumber else {
                                    unreadable += 1
                                    continue
                                }
                                bytes = length.int64Value
                            }
                            measuredFiles += 1
                            record(max(0, bytes), path)
                        }
                    } catch {
                        unreadable += 1
                    }
                }
            }
        }

        func savedAppLocation(_ path: [String]) -> (String, String)? {
            guard path.starts(with: ["Library", "Application Support"]), path.count >= 4 else { return nil }
            if path[2] == "ForgeAppManifests", path.count == 4,
               let id = jsonStem(path[3]), appFolders[id] != nil {
                return (id, "Forge app metadata")
            }
            guard path[2] == "HTMLApp", path.count >= 5 else { return nil }
            let folder = path[3]
            let filename = path[4]
            switch folder {
            case "SourceCache", "WebsitePending":
                guard appFolders[filename] != nil else { return nil }
                if folder == "WebsitePending" { return (filename, "Pending website updates") }
                if path.count > 5, path[5] == "native-imports" { return (filename, "Imported files and media") }
                if path.count > 5, path[5] == "native-outputs" { return (filename, "Generated files and media") }
                return (filename, "Source cache and offline website files")
            case "WebsiteSourceManifests":
                guard let id = jsonStem(filename), appFolders[id] != nil else { return nil }
                return (id, "Website source metadata")
            case "PortableAppData":
                if let stem = jsonStem(filename), let ids = safeIDs[stem], ids.count == 1 {
                    return (ids[0], "Saved key/value data")
                }
                for suffix in [".sqlite", ".sqlite-wal", ".sqlite-shm", ".sqlite-journal"] where filename.hasSuffix(suffix) {
                    let stem = String(filename.dropLast(suffix.count))
                    if let ids = safeIDs[stem], ids.count == 1 { return (ids[0], "SQLite and vector data") }
                }
                return nil
            case "RuntimeState", "SelectedStyles":
                guard let stem = jsonStem(filename),
                      let ids = (folder == "RuntimeState" ? asciiIDs : safeIDs)[stem], ids.count == 1 else { return nil }
                return (ids[0], folder == "RuntimeState" ? "Saved browser state" : "Forge style references")
            default:
                return nil
            }
        }

        scan(home) { bytes, path in
            if path.starts(with: ["tmp", HTMLAppGPUCache.directoryName]) {
                gpuFiles.add(bytes, path: path.dropFirst(2))
            } else if path == ["Library", "Application Support", "HTMLApp", "library.json"] {
                libraryBytes = bytes
            } else if let (id, category) = savedAppLocation(path), let folder = appFolders[id] {
                folder.add(bytes, path: ([category] + path)[...])
            } else {
                shared.add(bytes, path: ([sharedCategory(path)] + path)[...])
            }
        }
        if let group {
            scan(group) { bytes, path in
                shared.add(bytes, path: (["Shared App Group"] + path)[...])
            }
        }
        scan(bundle) { bytes, path in installed.add(bytes, path: path[...]) }

        // The library is one JSON file. Allocate its measured size by encoded entry
        // weight so the per-app estimates and shared remainder add up exactly.
        let encoder = JSONEncoder()
        let weights = apps.map { (try? encoder.encode($0).count) ?? 0 }
        let totalWeight = weights.reduce(0, +)
        var remaining = libraryBytes
        if totalWeight > 0 {
            for (app, weight) in zip(apps, weights) where weight > 0 {
                let share = min(remaining, Int64(Double(libraryBytes) * Double(weight) / Double(totalWeight)))
                remaining -= share
                appFolders[app.id]?.add(share, path: ["Library entry (estimate)"][...])
            }
        }
        if remaining > 0 {
            shared.add(remaining, path: ["Library and backups", "library.json (unassigned)"][...])
        }
        let rows = apps.map { app in
            App(id: app.id, name: app.name, categories: appFolders[app.id]?.nodes() ?? [])
        }.sorted { lhs, rhs in
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
        let sharedNodes = shared.nodes()
        let whisper = sharedNodes.first { $0.name == whisperCategory }
        return Self(apps: rows, shared: sharedNodes.filter { $0.id != whisper?.id },
                    whisper: whisper,
                    gpu: Node(id: "/gpu", name: "GPU temporary files", bytes: gpuFiles.bytes,
                              children: gpuFiles.nodes(prefix: "/gpu")),
                    gpuFolderCount: gpuFiles.children.keys.filter { $0.hasPrefix("mpsgraph-") }.count,
                    bundle: installed.nodes(),
                    unreadableCount: unreadable, measuredFileCount: measuredFiles)
    }

    private static func jsonStem(_ filename: String) -> String? {
        filename.hasSuffix(".json") ? String(filename.dropLast(5)) : nil
    }

    private static let whisperCategory = "Whisper model files"

    private static func sharedCategory(_ path: [String]) -> String {
        let names = path.map { $0.lowercased() }
        // WhisperKit's Hub repository is argmaxinc/whisperkit-coreml.
        // Older local downloads can also be named by their Whisper variant.
        if names.contains(where: { $0.contains("whisperkit") || $0.hasPrefix("openai_whisper") }) {
            return whisperCategory
        }
        if names.contains("huggingface") { return "Other downloaded models" }
        if names.contains(where: { $0 == "webkit" || $0.hasPrefix("com.apple.webkit") }) {
            return "Shared WebKit data and caches"
        }
        if path.starts(with: ["Library", "Application Support", "HTMLApp"]) {
            if path.last?.hasPrefix("library.") == true { return "Library and backups" }
            if path.count > 3 { return path[3] == "WebsiteDownloads" ? "Website download staging" : "Other HTMLApp data" }
        }
        if path.first == "Documents" { return "Documents and downloads" }
        if path.first == "tmp" { return "Temporary files and exports" }
        if path.starts(with: ["Library", "Preferences"]) { return "Preferences" }
        if path.starts(with: ["Library", "Caches"]) { return "Other caches" }
        if path.starts(with: ["Library", "Application Support"]) { return "Other application support files" }
        return "Other container files"
    }
}
