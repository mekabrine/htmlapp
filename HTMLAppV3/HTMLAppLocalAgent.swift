import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Small, permission-gated on-device inference. Cloud fallback, when
/// explicitly requested and confirmed, is handled by NativeAPIBridge.
/// Apple's on-device model retains its device and context limitations.
enum HTMLAppLocalAgent {
    enum LocalError: LocalizedError {
        case unavailable(String), invalidResult, invalidInput, thermal
        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): return reason
            case .invalidResult: return "The on-device model did not produce the requested response format."
            case .invalidInput: return "Local model prompts must be short and nonempty."
            case .thermal: return "Local inference is paused because the device is overheating."
            }
        }
    }

    static var availabilityMessage: String? { HTMLAppOfflineForge.availabilityMessage }

    static func complete(prompt: String, system: String, json: Bool,
                         structured: Bool = false) async throws -> [String: Any] {
        guard let reason = availabilityMessage else {
            guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  prompt.utf8.count <= 4000, system.utf8.count <= 1200 else {
                throw LocalError.invalidInput
            }
            guard ProcessInfo.processInfo.thermalState != .critical else {
                throw LocalError.thermal
            }
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                return try await infer(prompt: prompt, system: system,
                                       json: json, structured: structured)
            }
            #endif
            throw LocalError.unavailable("Foundation Models is unavailable in this build.")
        }
        throw LocalError.unavailable(reason)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct LocalStructuredAnswer {
        @Guide(description: "A factual direct answer to the user's request")
        var answer: String

        @Guide(description: "A one-sentence summary of the direct answer")
        var summary: String

        @Guide(description: "Whether the assistant can answer reliably from available information")
        var confident: Bool
    }

    @available(iOS 26.0, *)
    private static func infer(prompt: String, system: String,
                              json: Bool, structured: Bool) async throws -> [String: Any] {
        try Task.checkCancellation()
        let instruction = system + (json ?
            "\nRespond with one JSON object or array only. Do not use Markdown." : "")
        let session = LanguageModelSession(instructions: instruction)
        if structured {
            let response = try await session.respond(
                to: prompt, generating: LocalStructuredAnswer.self
            )
            try Task.checkCancellation()
            let item = response.content
            let payload: [String: Any] = [
                "answer": item.answer, "summary": item.summary,
                "confident": item.confident
            ]
            let data = try JSONSerialization.data(withJSONObject: payload,
                                                   options: [.sortedKeys])
            guard let text = String(data: data, encoding: .utf8) else {
                throw LocalError.invalidResult
            }
            return ["text": text, "json": payload,
                    "answer": item.answer, "summary": item.summary,
                    "confident": item.confident, "format": "structured"]
        }
        let response = try await session.respond(to: prompt)
        try Task.checkCancellation()
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LocalError.invalidResult }
        if json {
            guard let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  object is [String: Any] || object is [Any] else {
                throw LocalError.invalidResult
            }
            return ["text": text, "format": "json"]
        }
        return ["text": text, "format": "text"]
    }
    #endif
}
