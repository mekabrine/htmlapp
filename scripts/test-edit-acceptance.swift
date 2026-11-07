import Foundation

@main struct Tests {
    static let valid = """
    <html><head><script type="application/json" id="htmlapp-navigation">
    {"items":[{"id":"home","title":"Home","symbol":"house"},{"id":"settings","title":"Settings","symbol":"gearshape"}],"selected":"home"}
    </script></head><body><section data-htmlapp-screen="home">Home</section><section data-htmlapp-screen='settings'>Settings</section></body></html>
    """
    static func main() {
        precondition(!ForgeEditAcceptance.issues(before: "<html>a</html>", after: "<html>a</html>", request: "fix it").isEmpty)
        precondition(!ForgeEditAcceptance.issues(before: "<html>a</html>", after: "<html>a</html><!-- claimed success -->", request: "fix it").isEmpty)
        precondition(!ForgeEditAcceptance.issues(before: "old", after: "<nav>Home</nav>", request: "use the built in tab bar").isEmpty)
        precondition(!ForgeEditAcceptance.hasNativeNavigation("<!-- htmlapp-navigation -->"))
        precondition(!ForgeEditAcceptance.hasNativeNavigation(#"<script type="application/json" id="htmlapp-navigation">{"items":[{"id":"home"}]}</script>"#))
        precondition(!ForgeEditAcceptance.hasNativeNavigation(valid.replacingOccurrences(of: "data-htmlapp-screen='settings'", with: "data-htmlapp-screen='profile'")))
        precondition(ForgeEditAcceptance.hasNativeNavigation(valid))
        precondition(ForgeEditAcceptance.issues(before: "old", after: valid, request: "use the built in tab bar").isEmpty)
        precondition(ForgeEditAcceptance.hasNativeNavigation("<section data-htmlapp-screen='home'></section><section data-htmlapp-screen='settings'></section><script>HTMLAppNative.screens.configure({items:[]})</script>"))
        precondition(ForgeEditAcceptance.issues(before: "let x='a b'", after: "let x='ab'", request: "remove the space").isEmpty)
        precondition(!ForgeEditAcceptance.requiresNativeTabs("remove native tabs"))
        print("Edit acceptance and native navigation fixtures passed.")
    }
}
