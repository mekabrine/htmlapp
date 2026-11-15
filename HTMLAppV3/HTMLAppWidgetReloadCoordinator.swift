import Foundation
import WidgetKit

/// WidgetKit owns the actual render time. This coalesces nearby committed writes
/// without delaying user-driven changes by minutes or polling in the background.
enum HTMLAppWidgetReloadCoordinator {
    private static var pending: DispatchWorkItem?
    private static var lastReload = Date.distantPast

    static func request() {
        DispatchQueue.main.async {
            // Send the first committed change immediately. Coalesce bursts
            // into one trailing request instead of postponing every update.
            if Date().timeIntervalSince(lastReload) >= 0.1 {
                flushOnMain()
                return
            }
            pending?.cancel()
            let work = DispatchWorkItem { flushOnMain() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        }
    }

    static func flush() {
        if Thread.isMainThread { flushOnMain() }
        else { DispatchQueue.main.async { flushOnMain() } }
    }

    private static func flushOnMain() {
        pending?.cancel()
        pending = nil
        lastReload = Date()
        // Refresh every registered Home/Lock Screen kind. Never depend on
        // killing the containing app to make the system reread shared data.
        WidgetCenter.shared.reloadAllTimelines()
    }
}

