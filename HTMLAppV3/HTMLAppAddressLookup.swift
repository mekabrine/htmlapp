import Foundation
import CoreLocation

/// Reverse geocodes coordinates only after the saved app's location consent.
@MainActor
enum HTMLAppAddressLookup {
    static func reverse(latitude: Double, longitude: Double) async throws -> [String: Any] {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw LookupError.invalidCoordinates
        }
        let geocoder = CLGeocoder()
        let marks = try await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: latitude, longitude: longitude))
        guard let mark = marks.first else { throw LookupError.noAddress }
        let number = mark.subThoroughfare ?? ""
        let road = mark.thoroughfare ?? ""
        let street = [number, road].filter { !$0.isEmpty }.joined(separator: " ")
        let display = [
            street, mark.locality ?? "", mark.administrativeArea ?? "",
            mark.postalCode ?? "", mark.country ?? ""
        ].filter { !$0.isEmpty }.joined(separator: ", ")
        guard !display.isEmpty else { throw LookupError.noAddress }
        return [
            "formattedAddress": display,
            "street": street,
            "houseNumber": number,
            "road": road,
            "city": mark.locality ?? "",
            "region": mark.administrativeArea ?? "",
            "postalCode": mark.postalCode ?? "",
            "country": mark.country ?? "",
            "source": "Apple CoreLocation reverse geocoding",
            "approximate": true
        ]
    }
    /// Geocode a user-supplied address. This is not a way to infer the
    /// device's location; no GPS reading is requested or returned.
    static func geocode(_ raw: String) async throws -> [String: Any] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...180).contains(query.count) else { throw LookupError.invalidQuery }
        let matches = try await CLGeocoder().geocodeAddressString(query)
        let results: [[String: Any]] = matches.prefix(5).compactMap { mark in
            guard let coordinate = mark.location?.coordinate,
                  CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            let components = [
                mark.name ?? "", mark.locality ?? "",
                mark.administrativeArea ?? "", mark.country ?? ""
            ].filter { !$0.isEmpty }
            return [
                "latitude": coordinate.latitude,
                "longitude": coordinate.longitude,
                "formattedAddress": components.joined(separator: ", "),
                "city": mark.locality ?? "",
                "region": mark.administrativeArea ?? "",
                "country": mark.country ?? "",
                "approximate": true
            ]
        }
        guard !results.isEmpty else { throw LookupError.noAddress }
        return ["results": results, "source": "Apple CoreLocation geocoding"]
    }

    /// Offline great-circle distance; the caller chooses both coordinates.
    /// It does not obtain the user's position or use routing roads.
    static func distance(latitude1: Double, longitude1: Double,
                         latitude2: Double, longitude2: Double) throws -> [String: Any] {
        guard [latitude1, longitude1, latitude2, longitude2].allSatisfy({ $0.isFinite }),
              (-90...90).contains(latitude1), (-90...90).contains(latitude2),
              (-180...180).contains(longitude1), (-180...180).contains(longitude2)
        else { throw LookupError.invalidCoordinates }
        let rad = Double.pi / 180
        let p1 = latitude1 * rad
        let p2 = latitude2 * rad
        let dp = (latitude2 - latitude1) * rad
        let dl = (longitude2 - longitude1) * rad
        let haversine = pow(sin(dp / 2), 2) +
            cos(p1) * cos(p2) * pow(sin(dl / 2), 2)
        let meters = 2 * 6_371_008.8 * asin(min(1, sqrt(max(0, haversine))))
        return ["meters": meters, "kilometers": meters / 1000,
                "miles": meters / 1609.344, "kind": "great_circle"]
    }

    enum LookupError: LocalizedError {
        case invalidCoordinates, noAddress, invalidQuery
        var errorDescription: String? {
            switch self {
            case .invalidCoordinates: return "Latitude or longitude is invalid."
            case .noAddress: return "No matching address or location was available."
            case .invalidQuery: return "Provide a short, non-empty address or place name."
            }
        }
    }
}
