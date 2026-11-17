import XCTest
import Foundation

final class ForgeTranscriptionTests: XCTestCase {
    /// The mock response is carried in each request's test session, avoiding
    /// mutable global response handlers when XCTest runs tests in parallel.
    private func transcribe(status: Int, response: String) async throws -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try Data(repeating: 0, count: 100).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TranscriptionMock.self]
        config.httpAdditionalHeaders = ["X-Test-Status": String(status), "X-Test-Response": response]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        return try await ForgeTranscriptionTransport.transcribe(fileURL: file, session: session)
    }

    func testSuccessfulTranscriptionTrimsWhitespace() async throws {
        let words = try await transcribe(status: 200, response: "{\"success\":true,\"text\":\"  Make a habit tracker  \"}")
        XCTAssertEqual(words, "Make a habit tracker")
    }

    func testQuotaAuthenticationAndServerFailuresDoNotBecomeTranscripts() async {
        for status in [401, 429, 500] {
            do {
                _ = try await transcribe(status: status, response: "{\"success\":true,\"text\":\"Do not accept this\"}")
                XCTFail("Accepted HTTP \(status)")
            } catch { XCTAssertEqual((error as? URLError)?.code, .badServerResponse) }
        }
    }

    func testEmptyAndMalformedResponsesFail() async {
        for response in ["{}", "not JSON", "{\"success\":true,\"text\":\"  \"}", "{\"success\":true,\"text\":123}", "{\"text\":\"Missing success flag\"}"] {
            do {
                _ = try await transcribe(status: 200, response: response)
                XCTFail("Accepted an invalid transcript")
            } catch { /* The caller retains the recording for fallback/retry. */ }
        }
    }

    func testServiceFailureIsRejectedEvenWithHTTP200() async {
        do {
            _ = try await transcribe(status: 200, response: "{\"success\":false,\"text\":\"Do not accept this\"}")
            XCTFail("Accepted service failure as a transcript")
        } catch { XCTAssertEqual((error as? URLError)?.code, .cannotParseResponse) }
    }

    func testInvalidAudioSizeFailsBeforeNetworkUpload() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: file) }
        for size in [0, 44, 25_000_001] {
            FileManager.default.createFile(atPath: file.path, contents: Data())
            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: UInt64(size))
            try handle.close()
            do {
                _ = try await ForgeTranscriptionTransport.transcribe(fileURL: file)
                XCTFail("Accepted invalid audio size \(size)")
            } catch { XCTAssertEqual((error as NSError).domain, "ForgeTranscription") }
        }
    }
}

private final class TranscriptionMock: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.url?.absoluteString, "https://notetakers.vipresearch.ca/stt/v1/transcribe")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=Forge-") == true)
        let status = Int(request.value(forHTTPHeaderField: "X-Test-Status") ?? "500") ?? 500
        let value = request.value(forHTTPHeaderField: "X-Test-Response") ?? ""
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(value.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
