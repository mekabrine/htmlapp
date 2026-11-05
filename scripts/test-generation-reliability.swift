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
        let icon = "<link href='data:image/png;base64," + String(repeating: "A", count: 200_000)
            + "' rel='apple-touch-icon icon'>"
        let photo = "<img src='data:image/png;base64,appPhoto'>"
        let stylesheet = "<link rel='stylesheet' href='data:text/css,body{}'>"
        let original = "<html><head>" + icon + stylesheet + "</head><body>" + photo + "</body></html>"
        let context = ForgeEditIconContext(original)
        precondition(!context.html.contains(icon))
        precondition(context.html.contains(photo) && context.html.contains(stylesheet))
        let patched = context.html.replacingOccurrences(of: "<body>", with: "<body><p>Edited</p>")
        let restored = context.restoringIcons(in: patched)
        precondition(restored.contains(icon) && restored.contains("<p>Edited</p>"))
        precondition(ForgeEditIconContext(restored).html == patched.replacingOccurrences(of: "</head>", with: "\n</head>"))
        print("Provider completion and atomic patch regressions passed.")
    }
}
