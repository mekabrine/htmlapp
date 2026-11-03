import Foundation
import Network

/// A process-scoped connectivity snapshot, not a request to any domain.
/// Neither a satisfied path nor its interface class proves an API is reachable.
@MainActor
final class HTMLAppNetworkStatus {
    static let shared = HTMLAppNetworkStatus()
    static let notification = Notification.Name("HTMLAppNetworkPathChanged")

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "htmlapp.network-path", qos: .utility)
    private var latest: [String: Any] = [
        "status": "unknown",
        "online": false,
        "interface": "unknown",
        "expensive": false,
        "constrained": false
    ]

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let kind: String
            if path.usesInterfaceType(.wifi) { kind = "wifi" }
            else if path.usesInterfaceType(.cellular) { kind = "cellular" }
            else if path.usesInterfaceType(.wiredEthernet) { kind = "ethernet" }
            else { kind = "other" }
            let state: [String: Any] = [
                "status": path.status == .satisfied ? "satisfied" :
                    (path.status == .unsatisfied ? "unsatisfied" : "requires_connection"),
                "online": path.status == .satisfied,
                "interface": kind,
                "expensive": path.isExpensive,
                "constrained": path.isConstrained
            ]
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.latest = state
                NotificationCenter.default.post(name: Self.notification,
                                                object: nil, userInfo: state)
            }
        }
        monitor.start(queue: queue)
    }

    func snapshot() -> [String: Any] { latest }
}
