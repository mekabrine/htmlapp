import Foundation

enum HTMLAppStorageCleanup {
    struct Result: Sendable {
        var bytes: Int64 = 0
        var removed = 0
        var failed = 0
    }

    static func clearUnnecessaryFiles() async -> Result {
        await Task.detached(priority: .utility) {
            var result = Result()
            let manager = FileManager.default
            let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first
            let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let roots = [caches, support?.appendingPathComponent("HTMLApp/WebsiteDownloads", isDirectory: true)].compactMap { $0 }
            for root in roots { removeChildren(of: root, manager: manager, result: &result) }

            // Temp exports older than this running process are disposable. Keep
            // current-session files and let the specialized GPU validator
            // remove only completed MPSGraph archives.
            let cutoff = Date().addingTimeInterval(-15 * 60)
            if let entries = try? manager.contentsOfDirectory(at: manager.temporaryDirectory,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]) {
                for entry in entries where entry.lastPathComponent != HTMLAppGPUCache.directoryName {
                    guard let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey]),
                          values.isSymbolicLink != true,
                          let modified = values.contentModificationDate, modified < cutoff else { continue }
                    remove(entry, manager: manager, result: &result)
                }
            }
            let gpu = HTMLAppGPUCache.clearCompleted()
            result.bytes += gpu.bytes
            result.removed += gpu.removed
            result.failed += gpu.failed
            return result
        }.value
    }

    private static func removeChildren(of root: URL, manager: FileManager, result: inout Result) {
        guard let entries = try? manager.contentsOfDirectory(at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return }
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
            remove(entry, manager: manager, result: &result)
        }
    }

    private static func remove(_ url: URL, manager: FileManager, result: inout Result) {
        let bytes = allocatedBytes(url, manager: manager)
        do {
            try manager.removeItem(at: url)
            result.bytes += bytes
            result.removed += 1
        } catch { result.failed += 1 }
    }

    private static func allocatedBytes(_ url: URL, manager: FileManager) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        var total: Int64 = 0
        func add(_ file: URL) {
            guard let values = try? file.resourceValues(forKeys: keys), values.isSymbolicLink != true else { return }
            if values.isRegularFile == true {
                let allocated = max(values.totalFileAllocatedSize ?? 0, values.fileAllocatedSize ?? 0)
                total += Int64(allocated > 0 ? allocated : values.fileSize ?? 0)
            }
        }
        add(url)
        if let enumerator = manager.enumerator(at: url, includingPropertiesForKeys: Array(keys)) {
            for case let file as URL in enumerator { add(file) }
        }
        return total
    }
}
