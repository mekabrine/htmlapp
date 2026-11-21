import Security
import CoreLocation
import MapKit

@MainActor
enum HTMLAppPlaceLookup {
    struct Place {
        let name: String
        let latitude: Double
        let longitude: Double
        let distanceMeters: Double

        var payload: [String: Any] {
            ["name": name, "latitude": latitude, "longitude": longitude, "distanceMeters": distanceMeters]
        }
    }

    static func nearby(query: String, latitude: Double, longitude: Double) async throws -> [Place] {
        let center = CLLocation(latitude: latitude, longitude: longitude)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: center.coordinate,
                                            latitudinalMeters: 1_200, longitudinalMeters: 1_200)
        let search = MKLocalSearch(request: request)
        let deadline = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { search.cancel() }
        }
        defer { deadline.cancel() }
        let response = try await withTaskCancellationHandler {
            try await search.start()
        } onCancel: {
            Task { @MainActor in search.cancel() }
        }
        try Task.checkCancellation()

        let nearby = response.mapItems.compactMap { item -> Place? in
            guard let name = item.name, !name.isEmpty, let location = item.placemark.location else { return nil }
            let distance = location.distance(from: center)
            // MapKit treats the search region as a hint.
            guard distance <= 600 else { return nil }
            return Place(name: name, latitude: location.coordinate.latitude,
                         longitude: location.coordinate.longitude, distanceMeters: distance)
        }.sorted { $0.distanceMeters < $1.distanceMeters }
        return Array(nearby.prefix(5))
    }

    static func drivingETA(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> [String: Double] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile
        let directions = MKDirections(request: request)
        let deadline = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if !Task.isCancelled { directions.cancel() }
        }
        defer { deadline.cancel() }
        let eta = try await directions.calculateETA()
        return ["distanceMeters": eta.distance, "expectedTravelTimeSeconds": eta.expectedTravelTime]
    }
}

/// A device-only keychain item in the same per-app namespace as secureStorage.
@MainActor
enum ForgeVenueSeed {
    static func save(_ place: HTMLAppPlaceLookup.Place, appID: String) throws {
        let data = try JSONSerialization.data(withJSONObject: place.payload)
        let key = query(appID)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(key.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func load(_ appID: String) -> HTMLAppPlaceLookup.Place? {
        var request = query(appID)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = payload["name"] as? String, let latitude = payload["latitude"] as? Double,
              let longitude = payload["longitude"] as? Double,
              let distance = payload["distanceMeters"] as? Double else { return nil }
        return HTMLAppPlaceLookup.Place(name: name, latitude: latitude, longitude: longitude, distanceMeters: distance)
    }

    static func remove(_ appID: String) { SecItemDelete(query(appID) as CFDictionary) }

    private static func query(_ appID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.mekabrine.htmlapp.native." + appID,
         kSecAttrAccount as String: "forge.confirmedVenue"]
    }
}
