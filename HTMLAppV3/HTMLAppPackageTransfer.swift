import Foundation
import UIKit
import Compression

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

// Bounded ZIP reader accepts STORE and standard raw DEFLATE, including
// archives with data descriptors. Directory sizes and CRCs are authoritative.
// The writer continues using STORE for deterministic, portable exports.
private enum StoredZip {
    struct Entry {
        let path: String
        let data: Data
    }

    private struct CentralRecord {
        let path: Data
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    static func write(entries: [Entry], to url: URL) throws {
        var archive = Data()
        var central: [CentralRecord] = []

        for entry in entries {
            guard let pathData = entry.path.data(using: .utf8),
                  pathData.count <= Int(UInt16.max),
                  entry.data.count <= Int(UInt32.max),
                  archive.count <= Int(UInt32.max) else {
                throw HTMLAppPackageError.invalidArchive
            }
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(archive.count)

            archive.appendLE(UInt32(0x04034b50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0x0800))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(crc)
            archive.appendLE(size)
            archive.appendLE(size)
            archive.appendLE(UInt16(pathData.count))
            archive.appendLE(UInt16(0))
            archive.append(pathData)
            archive.append(entry.data)

            central.append(.init(path: pathData, crc: crc, size: size, offset: offset))
        }

        let centralStart = UInt32(archive.count)
        for record in central {
            archive.appendLE(UInt32(0x02014b50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0x0800))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(record.crc)
            archive.appendLE(record.size)
            archive.appendLE(record.size)
            archive.appendLE(UInt16(record.path.count))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt32(0))
            archive.appendLE(record.offset)
            archive.append(record.path)
        }

        let centralSize = UInt32(archive.count) - centralStart
        guard central.count <= Int(UInt16.max) else { throw HTMLAppPackageError.invalidArchive }
        archive.appendLE(UInt32(0x06054b50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(central.count))
        archive.appendLE(UInt16(central.count))
        archive.appendLE(centralSize)
        archive.appendLE(centralStart)
        archive.appendLE(UInt16(0))
        try archive.write(to: url, options: .atomic)
    }

    private static let maxArchiveBytes = 96_000_000
    private static let maxEntryBytes = 32_000_000
    private static let maxTotalBytes = 128_000_000
    private static let maxEntries = 250

    static func read(from url: URL) throws -> [String: Data] {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maxArchiveBytes else { throw HTMLAppPackageError.archiveTooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 22, data.count <= maxArchiveBytes else {
            throw HTMLAppPackageError.invalidArchive
        }
        // The End of Central Directory can contain up to 65535 bytes of
        // archive comment. Search backwards instead of trusting local
        // headers (their sizes may be zero when bit 3 is set).
        let lower = max(0, data.count - 22 - 65535)
        var eocd: Int?
        for offset in stride(from: data.count - 22, through: lower, by: -1) {
            let signature: UInt32 = try data.readLE(at: offset)
            if signature == 0x06054b50 {
                let comment: UInt16 = try data.readLE(at: offset + 20)
                if offset + 22 + Int(comment) == data.count {
                    eocd = offset
                    break
                }
            }
        }
        guard let eocd else { throw HTMLAppPackageError.damagedArchive }
        let disk: UInt16 = try data.readLE(at: eocd + 4)
        let centralDisk: UInt16 = try data.readLE(at: eocd + 6)
        let entriesOnDisk: UInt16 = try data.readLE(at: eocd + 8)
        let count: UInt16 = try data.readLE(at: eocd + 10)
        let directorySize: UInt32 = try data.readLE(at: eocd + 12)
        let directoryOffset: UInt32 = try data.readLE(at: eocd + 16)
        guard disk == 0, centralDisk == 0, entriesOnDisk == count,
              Int(count) <= maxEntries,
              count != UInt16.max, directorySize != UInt32.max,
              directoryOffset != UInt32.max else {
            throw HTMLAppPackageError.archiveTooLarge
        }
        var cursor = Int(directoryOffset)
        let directoryEnd = cursor + Int(directorySize)
        guard directoryEnd <= eocd else { throw HTMLAppPackageError.damagedArchive }
        var result: [String: Data] = [:]
        var totalUncompressed = 0
        for _ in 0..<Int(count) {
            guard cursor + 46 <= directoryEnd else { throw HTMLAppPackageError.damagedArchive }
            let signature: UInt32 = try data.readLE(at: cursor)
            guard signature == 0x02014b50 else { throw HTMLAppPackageError.damagedArchive }
            let flags: UInt16 = try data.readLE(at: cursor + 8)
            let method: UInt16 = try data.readLE(at: cursor + 10)
            let expectedCRC: UInt32 = try data.readLE(at: cursor + 16)
            let compressedSize: UInt32 = try data.readLE(at: cursor + 20)
            let uncompressedSize: UInt32 = try data.readLE(at: cursor + 24)
            let nameLength: UInt16 = try data.readLE(at: cursor + 28)
            let extraLength: UInt16 = try data.readLE(at: cursor + 30)
            let commentLength: UInt16 = try data.readLE(at: cursor + 32)
            let localOffset: UInt32 = try data.readLE(at: cursor + 42)
            guard flags & 0x0001 == 0, flags & 0x0040 == 0,
                  localOffset != UInt32.max,
                  method == 0 || method == 8 else {
                throw HTMLAppPackageError.unsupportedCompression
            }
            let next = cursor + 46 + Int(nameLength) + Int(extraLength) + Int(commentLength)
            guard next <= directoryEnd else { throw HTMLAppPackageError.damagedArchive }
            let pathStart = cursor + 46
            guard let name = String(data: data[pathStart..<(pathStart + Int(nameLength))],
                                    encoding: .utf8) else {
                throw HTMLAppPackageError.damagedArchive
            }
            cursor = next
            guard isSafePath(name) else { throw HTMLAppPackageError.unsafePath }
            if name.hasSuffix("/") { continue }
            // macOS archive metadata is not app content.
            if name.hasPrefix("__MACOSX/") || name == ".DS_Store" ||
                name.hasSuffix("/.DS_Store") { continue }
            guard !result.keys.contains(name) else { throw HTMLAppPackageError.damagedArchive }
            let decodedLength = Int(uncompressedSize)
            let packedLength = Int(compressedSize)
            guard decodedLength <= maxEntryBytes,
                  totalUncompressed + decodedLength <= maxTotalBytes else {
                throw HTMLAppPackageError.archiveTooLarge
            }
            if method == 8 && packedLength == 0 && decodedLength > 0 {
                throw HTMLAppPackageError.damagedArchive
            }
            if method == 8 && packedLength > 0 &&
                decodedLength > packedLength * 400 {
                throw HTMLAppPackageError.archiveTooLarge
            }
            let local = Int(localOffset)
            guard local + 30 <= Int(directoryOffset) else {
                throw HTMLAppPackageError.damagedArchive
            }
            let localSignature: UInt32 = try data.readLE(at: local)
            let localMethod: UInt16 = try data.readLE(at: local + 8)
            let localNameLength: UInt16 = try data.readLE(at: local + 26)
            let localExtraLength: UInt16 = try data.readLE(at: local + 28)
            guard localSignature == 0x04034b50, localMethod == method else {
                throw HTMLAppPackageError.damagedArchive
            }
            let localNameStart = local + 30
            let dataStart = localNameStart + Int(localNameLength) + Int(localExtraLength)
            let dataEnd = dataStart + packedLength
            guard dataEnd <= Int(directoryOffset),
                  localNameStart + Int(localNameLength) <= data.count,
                  dataEnd <= data.count,
                  Data(data[localNameStart..<(localNameStart + Int(localNameLength))]) ==
                      Data(data[pathStart..<(pathStart + Int(nameLength))]) else {
                throw HTMLAppPackageError.damagedArchive
            }
            // With flag 0x0008 the local header may have zero sizes. Use
            // central-directory sizes and ignore the trailing descriptor.
            let compressed = Data(data[dataStart..<dataEnd])
            let content: Data
            if method == 0 {
                guard packedLength == decodedLength else { throw HTMLAppPackageError.damagedArchive }
                content = compressed
            } else {
                content = try inflate(compressed, expectedSize: decodedLength)
            }
            guard CRC32.checksum(content) == expectedCRC else {
                throw HTMLAppPackageError.damagedArchive
            }
            totalUncompressed += content.count
            result[name] = content
        }
        guard cursor == directoryEnd else { throw HTMLAppPackageError.damagedArchive }
        return result
    }

    private static func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        var output = Data(count: expectedSize)
        let decoded = output.withUnsafeMutableBytes { target in
            input.withUnsafeBytes { source in
                compression_decode_buffer(
                    target.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    expectedSize,
                    source.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decoded == expectedSize else { throw HTMLAppPackageError.damagedArchive }
        return output
    }

    private static func isSafePath(_ path: String) -> Bool {
        !path.isEmpty &&
        !path.hasPrefix("/") &&
        !path.contains("\\") &&
        !path.split(separator: "/").contains("..")
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var c = UInt32(value)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func readLE<T: FixedWidthInteger>(at offset: Int) throws -> T {
        guard offset >= 0, offset + MemoryLayout<T>.size <= count else {
            throw HTMLAppPackageError.invalidArchive
        }
        var value: T = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { buffer in
            copyBytes(to: buffer, from: offset..<(offset + MemoryLayout<T>.size))
        }
        return T(littleEndian: value)
    }
}
