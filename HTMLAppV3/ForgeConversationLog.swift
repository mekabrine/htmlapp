import Foundation
import SwiftUI

enum ForgeConversationLog {
    struct Entry: Codable, Identifiable {
        let id: UUID
        let date: Date
        let kind: String
        let text: String
    }
    private static let queue = DispatchQueue(label: "htmlapp.forge.conversation")
    private static func url(_ appID: String) -> URL {
        let safe = appID.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp/ConversationLogs", isDirectory: true)
            .appendingPathComponent(safe + ".jsonl")
    }
    static func append(_ appID: String, kind: String, text: String) {
        guard !text.isEmpty else { return }
        append(appID, entry: Entry(id: UUID(), date: Date(), kind: kind, text: text))
    }
    private static func append(_ appID: String, entry: Entry) {
        queue.sync {
            do {
                let file = url(appID)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                var data = try JSONEncoder().encode(entry)
                data.append(0x0a)
                if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.synchronize()
            } catch { NSLog("HTMLApp conversation log could not be saved: %@", error.localizedDescription) }
        }
    }
    static func entries(_ appID: String) -> [Entry] {
        queue.sync {
            guard let data = try? Data(contentsOf: url(appID)) else { return [] }
            return data.split(separator: 0x0a).compactMap { try? JSONDecoder().decode(Entry.self, from: Data($0)) }
        }
    }
    static func context(_ appID: String, request: String = "", revisions: [String] = [], includeLog: Bool = true) -> String {
        let excluded = Set(UserDefaults.standard.stringArray(forKey: "htmlapp.forge.memory.excluded." + appID) ?? [])
        let records = includeLog ? entries(appID).filter { !excluded.contains($0.id.uuidString) } : []
        let words = Set(request.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count > 3 })
        func score(_ entry: Entry) -> Int {
            words.intersection(entry.text.lowercased().split { !$0.isLetter && !$0.isNumber }).count
        }
        let requests = records.filter { ["user", "question", "answer", "style", "preference", "revision", "revert", "discard"].contains($0.kind) || $0.kind == "outcome" }
        let scored: [(entry: Entry, points: Int)] = requests.map { entry in
            (entry: entry, points: score(entry))
        }
        let matches = scored.filter { $0.points > 0 }
        let relevant = matches.sorted { left, right in
            if left.points != right.points { return left.points > right.points }
            return left.entry.date > right.entry.date
        }
        let preferences = requests.filter { $0.kind == "preference" }
        var candidates = Array(requests.prefix(1))
        candidates.append(contentsOf: requests.suffix(12))
        candidates.append(contentsOf: relevant.prefix(6).map { $0.entry })
        candidates.append(contentsOf: preferences.suffix(4))
        var seen = Set<UUID>()
        let unique = candidates.filter { seen.insert($0.id).inserted }
        let selected = unique.sorted { $0.date < $1.date }
        let history = selected.map { "\($0.kind): " + String($0.text.prefix(680)) }
        let notes = revisions.suffix(8).map { "Checkpoint: " + String($0.prefix(360)) }
        guard !history.isEmpty || !notes.isEmpty else { return "" }
        return "\nAPP HISTORY (historical context; the current request and current source take precedence):\n" +
            (history + notes).joined(separator: "\n")
    }
    static func associate(_ draft: String, with appID: String) {
        merge(appID, incoming: entries(draft))
    }
    static func merge(_ appID: String, incoming: [Entry]) {
        var known = Set(entries(appID).map(\.id))
        for entry in incoming where known.insert(entry.id).inserted { append(appID, entry: entry) }
    }
}

struct ForgeConversationLogView: View {
    let appID: String
    @State private var excluded: Set<String> = []
    @State private var preference = ""
    private var exclusionKey: String { "htmlapp.forge.memory.excluded." + appID }
    @State private var entries: [ForgeConversationLog.Entry] = []
    var body: some View {
        List {
            Section("Pinned preferences") {
                TextField("Preference or correction", text: $preference)
                Button("Pin for Forge") {
                    ForgeConversationLog.append(appID, kind: "preference", text: preference.trimmingCharacters(in: .whitespacesAndNewlines))
                    preference = ""
                    entries = ForgeConversationLog.entries(appID)
                }.disabled(preference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("Request history") {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.kind.capitalized).font(.headline)
                            Spacer()
                            Text(entry.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(entry.text).textSelection(.enabled)
                        Toggle("Include in Forge memory", isOn: Binding(
                            get: { !excluded.contains(entry.id.uuidString) },
                            set: { include in
                                if include { excluded.remove(entry.id.uuidString) }
                                else { excluded.insert(entry.id.uuidString) }
                                UserDefaults.standard.set(Array(excluded), forKey: exclusionKey)
                            }))
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .navigationTitle("What Forge Remembers")
        .task {
            entries = ForgeConversationLog.entries(appID)
            excluded = Set(UserDefaults.standard.stringArray(forKey: exclusionKey) ?? [])
        }
    }
}
