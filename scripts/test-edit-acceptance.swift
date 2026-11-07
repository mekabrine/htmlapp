import Foundation
@main struct Tests {
    static func main() {
        precondition(!ForgeEditAcceptance.issues(before: "<html>a</html>", after: "<html>a</html>", request: "fix it").isEmpty)
        precondition(!ForgeEditAcceptance.issues(before: "old", after: "<nav>Home</nav>", request: "use the built in tab bar").isEmpty)
        precondition(ForgeEditAcceptance.issues(before: "old", after: "HTMLAppNative.screens.configure({})", request: "use native tabs").isEmpty)
        precondition(ForgeEditAcceptance.issues(before: "let x='a b'", after: "let x='ab'", request: "remove the space").isEmpty)
        precondition(!ForgeEditAcceptance.requiresNativeTabs("remove native tabs"))
        print("Edit acceptance fixtures passed; source review and runtime navigation checks remain separate.")
    }
}
