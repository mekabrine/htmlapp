import Foundation
import NaturalLanguage
import SQLite3

/// Private, on-device sentence-vector retrieval over an app's SQLite documents.
///
/// The index is an ordinary SQLite table of normalized Float32 vectors; no
/// network request, cloud model, SQLite extension or embedding API key is used.
/// Generation is lazy and bounded to prevent untrusted HTML from causing an
/// unbounded model inference or database scan.
enum HTMLAppVectorSearch {
    enum SearchError: LocalizedError {
        case badQuery, embeddingsUnavailable, indexLimit, invalidIndex

        var errorDescription: String? {
            switch self {
            case .badQuery:
                return "Vector search requires a short query and a valid collection."
            case .embeddingsUnavailable:
                return "On-device sentence embeddings aren't available for this language/device."
            case .indexLimit:
                return "This saved app's local vector index reached its 1,000-document limit."
            case .invalidIndex:
                return "The private on-device vector index could not be created."
            }
        }
    }

    static func search(appID: String, collection: String,
                       query: String, limit: Int) throws -> [[String: Any]] {
        guard !collection.isEmpty, collection.count <= 80,
              collection.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              query.utf8.count <= 512 else {
            throw SearchError.badQuery
        }
        let lang = NLLanguageRecognizer.dominantLanguage(for: query) ?? .english
        guard let model = NLEmbedding.sentenceEmbedding(for: lang) ??
              NLEmbedding.sentenceEmbedding(for: .english),
              let queryVector = normalize(model.vector(for: query)) else {
            throw SearchError.embeddingsUnavailable
        }
        let modelKey = String(lang.rawValue.prefix(20))
        HTMLAppDocumentDatabase.lock.lock()
        defer { HTMLAppDocumentDatabase.lock.unlock() }
        let db = try HTMLAppDocumentDatabase.open(appID: appID)
        defer { sqlite3_close(db) }
        let schema = """
        CREATE TABLE IF NOT EXISTS document_embeddings (
          collection TEXT NOT NULL, id TEXT NOT NULL, model TEXT NOT NULL,
          vector BLOB NOT NULL, PRIMARY KEY(collection,id)
        );
        CREATE TRIGGER IF NOT EXISTS document_embedding_invalidate_insert
          AFTER INSERT ON documents BEGIN
          DELETE FROM document_embeddings WHERE collection=NEW.collection AND id=NEW.id;
        END;
        CREATE TRIGGER IF NOT EXISTS document_embedding_invalidate_update
          AFTER UPDATE ON documents BEGIN
          DELETE FROM document_embeddings WHERE collection=NEW.collection AND id=NEW.id;
        END;
        CREATE TRIGGER IF NOT EXISTS document_embedding_invalidate_delete
          AFTER DELETE ON documents BEGIN
          DELETE FROM document_embeddings WHERE collection=OLD.collection AND id=OLD.id;
        END;
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
            throw SearchError.invalidIndex
        }
        let sql = """
        SELECT documents.id,documents.body,document_embeddings.vector,
               document_embeddings.model
        FROM documents LEFT JOIN document_embeddings ON
          documents.collection=document_embeddings.collection AND
          documents.id=document_embeddings.id
        WHERE documents.collection=? ORDER BY documents.id LIMIT 1001
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw SearchError.invalidIndex }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, collection, -1, transient)
        var hits: [(id: String, document: Any, score: Double)] = []
        var scanned = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            scanned += 1
            guard scanned <= 1000 else { throw SearchError.indexLimit }
            guard let idPtr = sqlite3_column_text(statement, 0),
                  let bodyPtr = sqlite3_column_text(statement, 1) else { continue }
            let id = String(cString: idPtr)
            let body = String(cString: bodyPtr)
            guard let data = body.data(using: .utf8),
                  let document = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            let savedModel = sqlite3_column_text(statement, 3).map { String(cString: $0) }
            var vector: [Float]?
            if savedModel == modelKey,
               let raw = sqlite3_column_blob(statement, 2) {
                let count = Int(sqlite3_column_bytes(statement, 2))
                if count > 0, count <= 16_384, count.isMultiple(of: 4) {
                    var recovered = [Float](repeating: 0, count: count / 4)
                    let bytes = Data(bytes: raw, count: count)
                    _ = recovered.withUnsafeMutableBytes { target in
                        bytes.copyBytes(to: target)
                    }
                    if recovered.count == queryVector.count {
                        vector = recovered
                    }
                }
            }
            if vector == nil {
                let text = extractText(document)
                guard !text.isEmpty,
                      let computed = normalize(model.vector(for: text)) else { continue }
                vector = computed
                try store(db: db, collection: collection, id: id,
                          model: modelKey, vector: computed)
            }
            guard let vector, vector.count == queryVector.count else { continue }
            let score = zip(queryVector, vector).reduce(0.0) {
                $0 + Double($1.0) * Double($1.1)
            }
            guard score.isFinite else { continue }
            hits.append((id, document, max(-1, min(1, score))))
        }
        return hits.sorted { $0.score > $1.score }.prefix(max(1, min(limit, 50)))
            .map { ["id": $0.id, "document": $0.document, "score": $0.score] }
    }

    private static func extractText(_ document: Any) -> String {
        var values: [String] = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 4, values.joined(separator: " ").utf8.count < 2048 else { return }
            if let text = value as? String, !text.isEmpty {
                values.append(String(text.prefix(750)))
            } else if let array = value as? [Any] {
                for item in array.prefix(12) { visit(item, depth: depth + 1) }
            } else if let object = value as? [String: Any] {
                for key in object.keys.sorted().prefix(20) {
                    if let value = object[key] { visit(value, depth: depth + 1) }
                }
            }
        }
        visit(document, depth: 0)
        return String(values.joined(separator: " ").prefix(2048))
    }

    private static func normalize(_ values: [Double]?) -> [Float]? {
        guard let values, !values.isEmpty, values.count <= 4096 else { return nil }
        let energy = values.reduce(0.0) { $0 + $1 * $1 }
        guard energy.isFinite, energy > 0 else { return nil }
        let length = sqrt(energy)
        return values.map { Float($0 / length) }
    }

    private static func store(db: OpaquePointer, collection: String, id: String,
                              model: String, vector: [Float]) throws {
        let destructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let sql = "INSERT OR REPLACE INTO document_embeddings(collection,id,model,vector) VALUES(?,?,?,?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw SearchError.invalidIndex }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, collection, -1, destructor)
        sqlite3_bind_text(statement, 2, id, -1, destructor)
        sqlite3_bind_text(statement, 3, model, -1, destructor)
        let bytes = vector.withUnsafeBytes { Data($0) }
        _ = bytes.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, 4, buffer.baseAddress,
                              Int32(buffer.count), destructor)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SearchError.invalidIndex
        }
    }
}
