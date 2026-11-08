import Foundation
import WidgetKit

/// WidgetKit owns the actual render time. This coalesces nearby committed writes
/// without delaying user-driven changes by minutes or polling in the background.
enum HTMLAppWidgetReloadCoordinator {
    private static var pending = false

    static func request() {
        DispatchQueue.main.async {
            guard !pending else { return }
            pending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                pending = false
                for kind in HTMLAppWidgetKinds.published {
                    WidgetCenter.shared.reloadTimelines(ofKind: kind)
                }
                WidgetCenter.shared.reloadTimelines(ofKind: "HTMLAppVoiceCreate")
            }
        }
    }
}

