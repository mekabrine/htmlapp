import Foundation

@main
struct GenerationReliabilityTests {
    static func main() {
        for reason in ["length", "max_tokens", "content_filter"] {
            precondition(ForgeGenerationResponseGuard.failure(in: ["choices": [["finish_reason": reason]]]) != nil)
        }
        precondition(ForgeGenerationResponseGuard.failure(in: ["stop_reason": "max_tokens"]) != nil)
        precondition(ForgeGenerationResponseGuard.failure(in: ["delta": ["stop_reason": "max_tokens"]]) != nil)
        precondition(ForgeGenerationResponseGuard.failure(in: ["stop_reason": "end_turn"]) == nil)
        precondition(ForgeGenerationResponseGuard.failure(in: ["choices": [["finish_reason": "stop"]]]) == nil)
        precondition(ForgeGenerationResponseGuard.failure(in: ["error": ["message": "failed"]]) != nil)
        precondition(!ForgeGenerationResponseGuard.isTerminal(["choices": [["delta": ["content": "partial"]]]]))
        precondition(ForgeGenerationResponseGuard.isTerminal(["type": "message_stop"]))
        precondition(ForgeGenerationResponseGuard.isTerminal(["delta": ["stop_reason": "end_turn"]]))
        precondition(ForgeGenerationResponseGuard.isTerminal(["choices": [["finish_reason": "stop"]]]))
        func patch(_ search: String, _ replacement: String) -> String {
            "<<<<<<< SEARCH\n" + search + "\n=======\n" + replacement + "\n>>>>>>> REPLACE"
        }
        let first = patch("alpha", "one")
        let second = patch("beta", "two")
        precondition(HTMLPatchApplier.apply(first + "\n" + second, to: "alpha beta") == "one two")
        precondition(HTMLPatchApplier.apply(first + "\n<<<<<<< SEARCH\nbeta\n=======\ntwo", to: "alpha beta") == nil)
        precondition(HTMLPatchApplier.apply(first + "\ntrailing garbage", to: "alpha") == nil)
        precondition(HTMLPatchApplier.apply(patch("alpha", ""), to: "alpha beta") == " beta")
        precondition(HTMLPatchApplier.apply(first, to: "alpha alpha") == nil)
        precondition(HTMLPatchApplier.apply(first + "\n" + patch("missing", "x"), to: "alpha beta") == nil)
        precondition(HTMLPatchApplier.apply(patch("", "x"), to: "alpha") == nil)
        precondition(HTMLPatchApplier.apply(patch("const x = '=======';", "const x = 'ok';"),
                                          to: "const x = '=======';") == "const x = 'ok';")
        precondition(HTMLPatchApplier.apply(first.replacingOccurrences(of: "\n", with: "\r\n"), to: "alpha") == "one")
        print("Provider completion and atomic patch regressions passed.")
    }
}
