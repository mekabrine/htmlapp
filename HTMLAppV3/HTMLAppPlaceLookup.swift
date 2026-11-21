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
