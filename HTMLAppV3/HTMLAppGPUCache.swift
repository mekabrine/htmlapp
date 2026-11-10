import Foundation

enum HTMLAppGPUCache {
    static let directoryName = "com.apple.MetalPerformanceShadersGraph"
    static let threshold = 20
    static let batchSize = 10
    static let resultKey = "htmlapp.gpuCache.lastCleanup"

    // Scheduled before the first app screen or model load. Model initialization
    // also awaits this same task in case dictation is requested during startup.
    private static let startup = Date()
    static let maintenance = beginMaintenance()

    private static func beginMaintenance() -> Task<Void, Never> {
        let cutoff = startup
        return Task.detached(priority: .utility) {
            let root = FileManager.default.temporaryDirectory
            guard let result = prune(in: root, olderThan: cutoff) else { return }
            UserDefaults.standard.set([
                "date": Date(), "removed": result.removed, "bytes": result.bytes, "failed": result.failed
            ], forKey: resultKey)
        }
    }

    struct Result {
        var removed = 0
        var bytes: Int64 = 0
        var failed = 0
    }

    static func prune(in temporary: URL, olderThan cutoff: Date) -> Result? {
        let manager = FileManager.default
        let root = temporary.appendingPathComponent(directoryName, isDirectory: true)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let info = try? root.resourceValues(forKeys: keys),
              info.isDirectory == true, info.isSymbolicLink == false,
              let children = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)) else { return nil }

        let candidates = children.compactMap { url -> (URL, Date)? in
            guard url.lastPathComponent.range(of: #"^mpsgraph-[0-9]+-[0-9]+$"#, options: .regularExpression) != nil,
                  let date = completedEntryDate(url, keys: keys), date < cutoff else { return nil }
            return (url, date)
        }.sorted {
            $0.1 == $1.1 ? $0.0.lastPathComponent < $1.0.lastPathComponent : $0.1 < $1.1
        }
        guard candidates.count >= threshold else { return nil }

        var result = Result()
        var remaining = candidates.count
        var offset = 0
        while remaining >= threshold, offset + batchSize <= candidates.count {
            for (url, originalDate) in candidates[offset ..< offset + batchSize] {
                let freshURL = URL(fileURLWithPath: url.path, isDirectory: true)
                guard completedEntryDate(freshURL, keys: keys) == originalDate else {
                    remaining -= 1
                    continue
                }
                let bytes = allocatedBytes(in: freshURL)
                guard completedEntryDate(URL(fileURLWithPath: url.path, isDirectory: true), keys: keys) == originalDate else {
                    remaining -= 1
                    continue
                }
                do {
                    try manager.removeItem(at: freshURL)
                    result.removed += 1
                    result.bytes += bytes
                    remaining -= 1
                } catch {
                    result.failed += 1
                }
            }
            offset += batchSize
        }
        return result
    }

    private static func completedEntryDate(_ url: URL, keys: Set<URLResourceKey>) -> Date? {
        // Avoid following aliases or removing unfamiliar cache layouts. Include
        // archive timestamps because rewriting a file may leave its parent unchanged.
        guard let info = try? url.resourceValues(forKeys: keys),
              info.isDirectory == true, info.isSymbolicLink == false,
              let date = info.contentModificationDate else { return nil }
        let archiveKeys = keys.union([.isRegularFileKey])
        var latest = date
        for name in ["MPSGraphWeightsOriginalModuleArchiveFile", "optimizedModule_0"] {
            guard let file = try? url.appendingPathComponent(name).resourceValues(forKeys: archiveKeys),
                  file.isRegularFile == true, file.isSymbolicLink == false,
                  let modified = file.contentModificationDate else { return nil }
            latest = max(latest, modified)
        }
        return latest
    }

    private static func allocatedBytes(in directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            guard let info = try? url.resourceValues(forKeys: keys), info.isSymbolicLink == false else {
                files.skipDescendants()
                continue
            }
            if info.isRegularFile == true {
                let allocated = max(info.totalFileAllocatedSize ?? 0, info.fileAllocatedSize ?? 0)
                total += Int64(allocated > 0 ? allocated : info.fileSize ?? 0)
            }
        }
        return total
    }
}
