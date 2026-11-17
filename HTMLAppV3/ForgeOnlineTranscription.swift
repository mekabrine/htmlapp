import Foundation

/// Forge-only cloud dictation. Saved apps never inherit this upload permission.
enum ForgeOnlineTranscription {
    static var apiKey: String {
        get { KeychainValueStore.read(account: "forge-transcription-groq") ?? "" }
        set {
            let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { KeychainValueStore.delete(account: "forge-transcription-groq") }
            else { KeychainValueStore.write(value, account: "forge-transcription-groq") }
        }
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "forge.onlineTranscription") as? Bool != false && !apiKey.isEmpty
    }

    static func transcribe(fileURL: URL) async throws -> String {
        try await ForgeTranscriptionTransport.transcribe(fileURL: fileURL, apiKey: apiKey)
    }
}
