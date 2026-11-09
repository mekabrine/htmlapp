import Foundation
import WebKit

enum HTMLAppSourcePolicy {
    static var networkOnly: Bool { UserDefaults.standard.string(forKey: "htmlapp.sourcePolicy") == "networkOnly" }
    static var freshOnline: Bool { UserDefaults.standard.string(forKey: "htmlapp.sourcePolicy") != "standard" }
    /// Refresh HTTP caches once per process when warming WebKit in the Library.
    /// Launch never waits on the shared store's asynchronous cache maintenance.
    @MainActor private static var scheduledCacheRefresh = false

    @MainActor static func refreshCacheDuringWarmup() {
        guard !scheduledCacheRefresh, freshOnline,
              !HTMLAppOfflineCache.shared.isOffline || networkOnly else { return }
        scheduledCacheRefresh = true
        WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache],
            modifiedSince: .distantPast) {}
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
