import Foundation

/// Bundles the exact d.ts generated from the authoritative bridge schema and
/// attaches it to the coder/editor instructions. The registry still validates
/// runtime calls; TypeScript declarations alone never grant OS permissions.
enum ForgeNativeTypedCatalog {
    static let promptContract: String = {
        guard let url = Bundle.main.url(
            forResource: "htmlapp-native-api", withExtension: "d.ts"
        ), let content = try? String(contentsOf: url, encoding: .utf8),
          content.utf8.count < 35_000 else {
            // The app can still generate with the runtime capability registry
            // if an old/incomplete bundle was installed.
            return """
            Authoritative native method names:
            \(HTMLAppBridgeRegistry.methods.joined(separator: ", "))
            Only call supported methods after feature detection and permission.
            """
        }
        return """

        AUTHORITATIVE GENERATED NATIVE TYPESCRIPT API CONTRACT:
        The following declarations are bundled from scripts/native-capability-definitions.json.
        Use these exact method names, argument shapes and return types; do not
        invent methods, OS entitlements or capabilities. Confirm capability
        availability and permission before interacting with real user data.
        <htmlapp_native_api_typescript>
        \(content)
        </htmlapp_native_api_typescript>

        """
    }()
}
