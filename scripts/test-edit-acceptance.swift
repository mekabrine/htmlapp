import Foundation

@main struct Tests {
    static func main() {
        let request = "Use the built in iOS tab bar instead of an HTML one"
        let valid = """
        <html><head>
        <script type="application/json" id="htmlapp-navigation">
        {"items":[{"id":"home","title":"Home","symbol":"house"},{"id":"settings","title":"Settings","symbol":"gearshape"}],"selected":"home"}
        </script></head><body>
        <section data-htmlapp-screen="home">Home</section>
        <section data-htmlapp-screen="settings" hidden>Settings</section>
        </body></html>
        """
        precondition(!ForgeEditAcceptance.issues(before: "<html>a</html>", after: "<html>a</html>", request: "fix it").isEmpty)
        precondition(!ForgeEditAcceptance.issues(before: "old", after: "<nav>Home</nav>", request: request).isEmpty)
        precondition(ForgeEditAcceptance.issues(before: "old", after: "HTMLAppNative.screens.configure({})", request: "use native tabs").isEmpty)
        precondition(ForgeEditAcceptance.issues(before: "old", after: valid, request: request).isEmpty)
        precondition(!ForgeEditAcceptance.issues(before: "old", after: valid.replacingOccurrences(of: #""selected":"home""#, with: #""selected":"missing""#), request: request).isEmpty)
        precondition(!ForgeEditAcceptance.issues(before: "old", after: valid.replacingOccurrences(of: "settings\" hidden", with: "wrong\" hidden"), request: request).isEmpty)
        precondition(!ForgeEditAcceptance.issues(before: "old", after: valid.replacingOccurrences(of: #""symbol":"house""#, with: #""symbol":"""#), request: request).isEmpty)
        precondition(!ForgeEditAcceptance.issues(before: "old", after: valid.replacingOccurrences(of: #""items":[{"id":"home""#, with: #""items":[{"id":"settings""#), request: request).isEmpty)
        precondition(!ForgeEditAcceptance.issues(before: "old", after: "<script type=\"application/json\" id=\"htmlapp-navigation\">{invalid}</script>", request: request).isEmpty)
        precondition(ForgeEditAcceptance.issues(before: "let x='a b'", after: "let x='ab'", request: "remove the space").isEmpty)
        precondition(!ForgeEditAcceptance.requiresNativeTabs("remove native tabs"))
        precondition(ForgeEditAcceptance.requiresNativeTabs("Replace my fake bottom navigation with the system one"))
        print("Edit acceptance fixtures passed; source review and runtime navigation checks remain separate.")
    }
}
