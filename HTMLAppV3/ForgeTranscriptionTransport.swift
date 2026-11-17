import Foundation

/// Bounded transport with no app/settings dependencies, so failure handling can
/// be tested without a microphone, network credentials or private audio.
enum ForgeTranscriptionTransport {
    static func transcribe(fileURL: URL, session testSession: URLSession? = nil) async throws -> String {
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 44, size <= 25_000_000 else {
            throw NSError(domain: "ForgeTranscription", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Record up to five minutes at a time."])
        }
        try Task.checkCancellation()
        let boundary = "Forge-" + UUID().uuidString
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        for (name, value) in [("engine", "whisper")] {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"prompt.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        append("\r\n--\(boundary)--\r\n")
        var request = URLRequest(url: URL(string: "https://notetakers.vipresearch.ca/stt/v1/transcribe")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 40
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = testSession ?? URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { if testSession == nil { session.invalidateAndCancel() } }
        let (data, response) = try await session.upload(for: request, from: body)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // Never log provider bodies, credentials, audio or private transcripts.
            throw URLError(.badServerResponse)
        }
        struct Transcript: Decodable {
            let success: Bool
            let text: String
        }
        let result = try JSONDecoder().decode(Transcript.self, from: data)
        guard result.success else { throw URLError(.cannotParseResponse) }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw URLError(.cannotParseResponse) }
        return text
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
