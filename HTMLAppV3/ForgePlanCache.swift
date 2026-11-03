import Foundation

/// Small in-memory cache for the exact same Forge planning request.
/// It avoids repeated paid planner calls when retrying a generation, without
/// storing app ideas, provider credentials or plans on disk.
actor ForgePlanCache {
    static let shared = ForgePlanCache()

    private struct Entry {
        let result: AIPlanningResult
        let savedAt: Date
    }

    private var values: [String: Entry] = [:]
    private let lifetime: TimeInterval = 12 * 60
    private let maximumEntries = 16

    func read(_ key: String) -> AIPlanningResult? {
        prune()
        return values[key]?.result
    }

    func save(_ value: AIPlanningResult, for key: String) {
        prune()
        guard key.utf8.count <= 12_000 else { return }
        values[key] = Entry(result: value, savedAt: Date())
        if values.count > maximumEntries,
           let oldest = values.min(by: { $0.value.savedAt < $1.value.savedAt })?.key {
            values.removeValue(forKey: oldest)
        }
    }

    func clear() {
        values.removeAll()
    }

    private func prune() {
        let now = Date()
        values = values.filter { now.timeIntervalSince($0.value.savedAt) < lifetime }
    }
}
