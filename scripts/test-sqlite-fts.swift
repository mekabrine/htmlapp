import Foundation

// Lightweight stand-in for the app's sandbox path when testing the SQLite
// helper directly on the macOS GitHub Actions runner.
enum HTMLAppPortableDataStore {
    static func fileURL(appID: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("htmlapp-fts-test-" + appID + ".json")
    }
}

@main
struct SQLiteFullTextTests {
    static func main() throws {
        let app = UUID().uuidString
        defer { try? FileManager.default.removeItem(
            at: HTMLAppDocumentDatabase.databaseURL(appID: app)
        ) }
        func put(_ id: String, _ text: String) throws {
            _ = try HTMLAppDocumentDatabase.perform(
                appID: app, method: "db.put",
                args: ["collection": "notes", "id": id,
                       "document": ["title": text]]
            )
        }
        try put("first", "A portable journal for road trips")
        try put("second", "Tomorrow buy groceries")
        let matches = try HTMLAppDocumentDatabase.fullTextSearch(
            appID: app, collection: "notes", text: "portable journal", limit: 10
        )
        precondition(matches.count == 1 && matches.first?["id"] as? String == "first")
        // Existing indexed documents must remain searchable after updates,
        // without retaining old tokens from the replaced JSON row.
        try put("first", "Updated notes about camping")
        let gone = try HTMLAppDocumentDatabase.fullTextSearch(
            appID: app, collection: "notes", text: "journal", limit: 10
        )
        precondition(gone.isEmpty)
        let updated = try HTMLAppDocumentDatabase.fullTextSearch(
            appID: app, collection: "notes", text: "camping", limit: 10
        )
        precondition(updated.count == 1)
        _ = try HTMLAppDocumentDatabase.perform(
            appID: app, method: "db.delete",
            args: ["collection": "notes", "id": "first"]
        )
        let deleted = try HTMLAppDocumentDatabase.fullTextSearch(
            appID: app, collection: "notes", text: "camping", limit: 10
        )
        precondition(deleted.isEmpty)
        print("SQLite FTS5 indexing, updates and deletion fixtures passed.")
    }
}
