import Foundation

/// Forge-only cloud dictation. Saved apps never inherit this upload permission.
enum ForgeOnlineTranscription {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "forge.onlineTranscription") as? Bool != false
    }

    static func transcribe(fileURL: URL) async throws -> String {
        try await ForgeTranscriptionTransport.transcribe(fileURL: fileURL)
    }
}
