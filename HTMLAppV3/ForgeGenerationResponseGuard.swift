import Foundation

/// Shared by foreground and background completions. Partial provider output
/// must never become a successful edit just because it contains some HTML.
enum ForgeGenerationResponseGuard {
    static func failure(in object: [String: Any]) -> String? {
        let choice = (object["choices"] as? [[String: Any]])?.first
        let delta = object["delta"] as? [String: Any]
        let reason = ((choice?["finish_reason"] as? String)
            ?? (object["stop_reason"] as? String)
            ?? (delta?["stop_reason"] as? String) ?? "").lowercased()
        if ["length", "max_tokens", "model_context_window_exceeded"].contains(reason) {
            return "The AI provider reached its output or context limit. Incomplete code was not accepted; try a smaller change or increase the configured output limit."
        }
        if ["content_filter", "refusal"].contains(reason) {
            return "The AI provider declined this response. No generated changes were accepted."
        }
        if object["error"] != nil {
            return "The AI provider returned an error instead of a completed response."
        }
        return nil
    }

    static func isTerminal(_ object: [String: Any]) -> Bool {
        if object["type"] as? String == "message_stop" { return true }
        if let first = (object["choices"] as? [[String: Any]])?.first,
           let reason = first["finish_reason"] as? String, !reason.isEmpty { return true }
        if let delta = object["delta"] as? [String: Any],
           let reason = delta["stop_reason"] as? String, !reason.isEmpty { return true }
        return false
    }
}
