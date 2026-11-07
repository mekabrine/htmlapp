import Foundation
import WebKit

enum HTMLAppSourcePolicy {
    static var networkOnly: Bool { UserDefaults.standard.string(forKey: "htmlapp.sourcePolicy") == "networkOnly" }
    static var freshOnline: Bool { UserDefaults.standard.string(forKey: "htmlapp.sourcePolicy") != "standard" }
    /// Clears only HTTP resource caches. Cookies, localStorage and saved app data survive.
    @MainActor static func prepare(_ webView: WKWebView, then load: @escaping () -> Void) {
        guard freshOnline, !HTMLAppOfflineCache.shared.isOffline || networkOnly else { load(); return }
        webView.configuration.websiteDataStore.removeData(
            ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache],
            modifiedSince: .distantPast) { load() }
    }
    static var script: String {
        guard freshOnline else { return "" }
        return #"""
        (() => {
          const original = window.fetch.bind(window);
          window.fetch = (input, init = {}) => {
            // Honor explicit provider caching requirements. Default fresh reads.
            if (init.cache || (input instanceof Request && input.cache !== 'default')) return original(input, init);
            const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url, document.baseURI);
            return original(input, /^https?:$/.test(url.protocol) ? {...init, cache:'no-store'} : init);
          };
        })();
        """#
    }
}
