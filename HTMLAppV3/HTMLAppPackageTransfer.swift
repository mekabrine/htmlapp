import Foundation
import UIKit

struct HTMLAppPortableBundle: Codable {
    static let currentVersion = 6

    var formatVersion: Int
    var exportedAt: Date
    var apps: [SavedHTMLApp]
    var folders: [LibraryFolder]
    var links: [LibraryAppLink]
    var permissionChoices: [String: [String: String]]
    var sensorChoices: [String: String]
    var appData: [String: [String: String]]?
    var websiteStates: [String: WebsiteArchivePortableState]?
    var widgetDefinitions: [HTMLAppWidgetDefinition]?
    var backgroundJobs: [HTMLAppBackgroundFetchJob]?
    // Optional in older backups; never includes source data, permission grants
    // or user records. Imported metadata must be revalidated against HTML.
    var appManifests: [String: ForgeAppManifest]?
}

enum HTMLAppPackageError: LocalizedError {
    case invalidArchive
    case unsupportedVersion
    case missingManifest
    case unsafePath
    case archiveTooLarge
    case damagedArchive
    case unsupportedCompression

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "The selected file is not a valid HTMLApp backup."
        case .unsupportedVersion: return "This HTMLApp backup was created by a newer unsupported format."
        case .missingManifest: return "The HTMLApp backup is missing its package manifest."
        case .unsafePath: return "The HTMLApp backup contains an unsafe file path."
        case .archiveTooLarge: return "This backup exceeds HTMLApp's safe size limits. Export a smaller set of apps or omit cached personal data."
        case .damagedArchive: return "The backup contains damaged files (ZIP checksum mismatch), duplicate entries or an invalid ZIP directory."
        case .unsupportedCompression: return "This backup uses an unsupported ZIP method. Re-export from HTMLApp, or re-zip using Standard ZIP (Store or Deflate)."
        }
    }
}

enum HTMLAppPackageTransfer {
    private static let manifestName = "htmlapp-package.json"

    static func createArchive(
        apps: [SavedHTMLApp],
        folders: [LibraryFolder],
        links: [LibraryAppLink],
        includePersonalData: Bool = true
    ) throws -> URL {
        let appIDs = Set(apps.map(\.id))
        // Permission grants are deliberately not transferred. A received HTMLApp
        // must ask again on the destination device before sensitive native access.
        let permissionChoices: [String: [String: String]] = [:]
        let sensorChoices: [String: String] = [:]

        let bundle = HTMLAppPortableBundle(
            formatVersion: HTMLAppPortableBundle.currentVersion,
            exportedAt: Date(),
            apps: apps,
            folders: folders,
            links: links.filter { appIDs.contains($0.appID) },
            permissionChoices: permissionChoices,
            sensorChoices: sensorChoices,
            appData: includePersonalData ? Dictionary(uniqueKeysWithValues: apps.map {
                ($0.id, HTMLAppPortableDataStore.all(appID: $0.id))
            }) : nil,
            websiteStates: includePersonalData ? Dictionary(uniqueKeysWithValues: apps.compactMap { app in
                guard app.websiteSourceURL != nil else { return nil }
                return (app.id, WebsiteArchiveManager.shared.portableState(appID: app.id))
            }) : nil,
            widgetDefinitions: includePersonalData ? HTMLAppWidgetStore.all().filter { appIDs.contains($0.appID) } : nil,
            backgroundJobs: includePersonalData ? HTMLAppBackgroundJobStore.all().filter { appIDs.contains($0.appID) } : nil,
            appManifests: Dictionary(uniqueKeysWithValues: apps.map { app in
                let manifest = ForgeAppManifestStore.load(for: app.id) ??
                    ForgeAppManifest.build(html: app.html,
                        model: ForgeSemanticAppModel.build(html: app.html, purpose: app.summary))
                var transport = manifest
                // Nearby sharing must not leak previous personal edit notes.
                if !includePersonalData { transport.editHistory = [] }
                return (app.id, transport)
            })
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        var entries: [StoredZip.Entry] = [
            .init(path: manifestName, data: try encoder.encode(bundle))
        ]

        if includePersonalData {
        for app in apps {
            let root = SourceCache.shared.baseURL(appID: app.id)
            if FileManager.default.fileExists(atPath: root.path) {
                for item in try recursiveFiles(at: root) {
                    // Only remove the known leading directory prefix. A
                    // global string replacement can corrupt nested filenames.
                    let prefix = root.path + "/"
                    guard item.path.hasPrefix(prefix) else { continue }
                    let relative = String(item.path.dropFirst(prefix.count))
                    guard isSafeRelativePath(relative) else { continue }
                    let data = try Data(contentsOf: item)
                    entries.append(.init(path: "cache/\(app.id)/\(relative)", data: data))
                }
            }
        }

        }

        let safeBase: String
        if apps.count == 1 {
            safeBase = safeFilename(apps[0].name)
        } else {
            safeBase = "HTMLApp-Backup-\(apps.count)-Apps"
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeBase + ".htmlapp.zip")
        try? FileManager.default.removeItem(at: url)
        try StoredZip.write(entries: entries, to: url)
        return url
    }

    static func readArchive(from url: URL) throws -> (bundle: HTMLAppPortableBundle, cacheFiles: [String: Data]) {
        let entries = try StoredZip.read(from: url)
        guard let manifest = entries[manifestName] else { throw HTMLAppPackageError.missingManifest }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let bundle = try? decoder.decode(HTMLAppPortableBundle.self, from: manifest) else {
            throw HTMLAppPackageError.invalidArchive
        }
        guard bundle.formatVersion <= HTMLAppPortableBundle.currentVersion else {
            throw HTMLAppPackageError.unsupportedVersion
        }

        var cache: [String: Data] = [:]
        for (path, data) in entries where path.hasPrefix("cache/") {
            guard isSafeRelativePath(path) else { throw HTMLAppPackageError.unsafePath }
            cache[path] = data
        }
        return (bundle, cache)
    }

    static func restoreCache(
        _ files: [String: Data],
        appIDMap: [String: String]
    ) throws {
        for (path, data) in files {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3, parts[0] == "cache",
                  let newID = appIDMap[parts[1]] else { continue }
            let relative = parts.dropFirst(2).joined(separator: "/")
            guard isSafeRelativePath(relative) else { throw HTMLAppPackageError.unsafePath }

            let root = SourceCache.shared.baseURL(appID: newID)
            let destination = root.appendingPathComponent(relative)
            let parent = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
    }

    private static func recursiveFiles(at root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true { urls.append(url) }
        }
        return urls
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return !path.split(separator: "/").contains("..")
    }

    private static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "HTMLApp" : String(cleaned.prefix(80))
    }
}
