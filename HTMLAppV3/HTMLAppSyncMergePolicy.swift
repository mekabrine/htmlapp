import Foundation
import CryptoKit

/// Three-way comparison: a single changed side can sync automatically. Two
/// different edits (including explicit clears) must be reviewed by the user.
enum HTMLAppSyncMergePolicy {
    enum Decision: Equatable { case equal, upload, download, conflict }
    static func fingerprint(_ values: [String: String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = (try? encoder.encode(values)) ?? Data()
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    static func decide(local: [String: String], cloud: [String: String], baseline: String?) -> Decision {
        let localHash = fingerprint(local), cloudHash = fingerprint(cloud)
        if localHash == cloudHash { return .equal }
        guard let baseline else { return .conflict }
        if cloudHash == baseline { return .upload }
        if localHash == baseline { return .download }
        return .conflict
    }
    static func baseline(id: String, kind: String) -> String? {
        UserDefaults.standard.string(forKey: "htmlapp.syncBaseline.\(kind).\(id)")
    }
    static func acknowledge(_ values: [String: String], id: String, kind: String) {
        UserDefaults.standard.set(fingerprint(values), forKey: "htmlapp.syncBaseline.\(kind).\(id)")
    }
}

enum HTMLAppSyncError: LocalizedError {
    case unavailable, disabled, changedDuringReview
    var errorDescription: String? {
        switch self {
        case .unavailable: return "iCloud Drive is unavailable. Check your account, iCloud Drive and signing profile. Your local apps are kept."
        case .disabled: return "Sync is off. Turn it on before resolving cloud changes."
        case .changedDuringReview: return "This app changed while you were reviewing it. Sync again and review the latest versions."
        }
    }
}
