import Foundation

/// In-memory launch allowance. Never persist or reset it on foreground/view changes.
struct ForgeTranscriptionSession {
    private(set) var canAttemptOnline = true

    mutating func claimOnlineAttempt(enabled: Bool) -> Bool {
        guard enabled, canAttemptOnline else { return false }
        canAttemptOnline = false
        return true
    }
}

/// Forge-only cloud dictation. Saved apps never inherit this upload permission.
@MainActor
enum ForgeOnlineTranscription {
    private static var session = ForgeTranscriptionSession()

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "forge.onlineTranscription") as? Bool != false
    }

    static var isAvailable: Bool { isEnabled && session.canAttemptOnline }

    static func transcribe(fileURL: URL) async throws -> String {
        try Task.checkCancellation()
        let bytes = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes > 44, bytes <= 25_000_000 else { throw URLError(.cannotDecodeRawData) }
        // Claim before the first suspension so concurrent recording views cannot
        // upload twice. Failure or cancellation after this point still counts.
        guard session.claimOnlineAttempt(enabled: isEnabled) else { throw URLError(.resourceUnavailable) }
        return try await ForgeTranscriptionTransport.transcribe(fileURL: fileURL)
    }
}
