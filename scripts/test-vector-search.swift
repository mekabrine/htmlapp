import Foundation
import NaturalLanguage

enum HTMLAppPortableDataStore {
    static func fileURL(appID: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("htmlapp-vector-test-" + appID + ".json")
    }
}

@main
struct VectorSearchTests {
    static func main() throws {
        let app = UUID().uuidString
        defer {
            try? FileManager.default.removeItem(
                at: HTMLAppDocumentDatabase.databaseURL(appID: app)
            )
        }
        do {
            _ = try HTMLAppVectorSearch.search(
                appID: app, collection: "../bad", query: "something", limit: 10
            )
            preconditionFailure("Invalid collection should be rejected")
        } catch HTMLAppVectorSearch.SearchError.badQuery {
            // Expected.
        }

        guard NLEmbedding.sentenceEmbedding(for: .english) != nil else {
            print("Local embedding model not installed on this macOS runner; input policy passed.")
            return
        }
        func put(_ id: String, _ title: String) throws {
            _ = try HTMLAppDocumentDatabase.perform(
                appID: app, method: "db.put",
                args: ["collection": "notes", "id": id,
                       "document": ["title": title]]
            )
        }
        try put("hike", "Trail hiking in the mountains")
        try put("work", "Business meeting on Wednesday")
        let results = try HTMLAppVectorSearch.search(
            appID: app, collection: "notes", query: "mountain hike", limit: 10
        )
        precondition(!results.isEmpty && results.count <= 2)
        precondition(results[0]["score"] as? Double != nil)
        try put("hike", "Updated road cycling journal")
        _ = try HTMLAppVectorSearch.search(
            appID: app, collection: "notes", query: "road cycling", limit: 10
        )
        _ = try HTMLAppDocumentDatabase.perform(
            appID: app, method: "db.delete",
            args: ["collection": "notes", "id": "hike"]
        )
        let afterDelete = try HTMLAppVectorSearch.search(
            appID: app, collection: "notes", query: "road cycling", limit: 10
        )
        precondition(afterDelete.allSatisfy { $0["id"] as? String != "hike" })
        print("Local SQLite sentence-vector search lifecycle passed.")
    }
}
