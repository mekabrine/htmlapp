# Semantic search in saved apps

```js
await HTMLAppNative.db.put('notes', 'trail', {
  title: 'Mountain hiking route',
  description: 'A day on the ridge trail.'
});
const matches = await HTMLAppNative.db.vectorSearch('notes', 'a trek in the mountains', 10);
console.log(matches.items); // id, document, semantic score
```

HTMLApp uses Apple's installed on-device `NLEmbedding` sentence model and an SQLite table of normalized Float32 vectors. No text or embeddings are sent to cloud services, and the index is isolated by the calling saved app's data directory. The index is created lazily and updated or invalidated as documents are inserted, replaced or deleted.

Limits: 1,000 documents searched per collection, 50 returned matches, 512-byte queries and bounded indexed content per document. The embedding model and language must be available on the device; no automatic downloads or server fallback are performed. If unavailable, catch the error and use `db.searchFullText()` or `db.search()` for local text search. This is deterministic on-device retrieval, not a general-purpose external vector database.
