import CoreLocation
import Foundation

/// Native location collection with explicit Always authorization. Does not run
/// HTML in the background or promise delivery after force quit.
@MainActor
final class HTMLAppBackgroundLocation: NSObject, CLLocationManagerDelegate {
    private static var sessions: [String: HTMLAppBackgroundLocation] = [:]
    private let manager = CLLocationManager()
    private let appID: String
    private var samples: [[String: Double]] = []
    private init(appID: String) { self.appID = appID; super.init(); manager.delegate = self }
    private static func file(_ appID: String) -> URL {
        SourceCache.shared.baseURL(appID: appID).appendingPathComponent("background-location.json")
    }
    static func enable(appID: String, distance: Double) -> [String: Any] {
        let session = sessions[appID] ?? HTMLAppBackgroundLocation(appID: appID)
        sessions[appID] = session
        session.manager.distanceFilter = max(10, min(1000, distance.isFinite ? distance : 25))
        session.manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        switch session.manager.authorizationStatus {
        case .notDetermined: session.manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: session.manager.requestAlwaysAuthorization()
        case .authorizedAlways: session.start()
        default: break
        }
        return status(appID: appID)
    }
    static func disable(appID: String) -> [String: Any] {
        sessions[appID]?.manager.stopUpdatingLocation(); sessions.removeValue(forKey: appID)
        return ["enabled": false]
    }
    static func status(appID: String) -> [String: Any] {
        guard let session = sessions[appID] else { return ["enabled": false, "authorization": "notRequested"] }
        let status = session.manager.authorizationStatus
        let authorization: String
        switch status {
        case .authorizedAlways: authorization = "always"
        case .authorizedWhenInUse: authorization = "whenInUse"
        case .denied: authorization = "denied"
        case .restricted: authorization = "restricted"
        default: authorization = "notDetermined"
        }
        return ["enabled": status == .authorizedAlways, "authorization": authorization]
    }
    static func read(appID: String) -> [[String: Double]] {
        guard let bytes = try? Data(contentsOf: file(appID)), bytes.count < 200_000,
              let records = try? JSONDecoder().decode([[String: Double]].self, from: bytes) else { return [] }
        return Array(records.suffix(500))
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways { start() }
        else { manager.stopUpdatingLocation() }
    }
    private func start() {
        guard manager.authorizationStatus == .authorizedAlways else { return }
        if samples.isEmpty { samples = Self.read(appID: appID) }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = true
        manager.startUpdatingLocation()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard HTMLPermissionStore.choice(for: .location, appID: appID) == .allow else {
            _ = Self.disable(appID: appID); return
        }
        for location in locations where location.horizontalAccuracy >= 0 {
            samples.append(["latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude,
                            "accuracy": location.horizontalAccuracy, "timestampMs": location.timestamp.timeIntervalSince1970 * 1000])
        }
        samples = Array(samples.suffix(500))
        if let data = try? JSONEncoder().encode(samples) { try? data.write(to: Self.file(appID), options: .atomic) }
    }
}
