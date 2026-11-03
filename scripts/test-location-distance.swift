import Foundation
import CoreLocation

@main
struct LocationDistanceRegressionTests {
    @MainActor
    static func main() throws {
        let zero = try HTMLAppAddressLookup.distance(
            latitude1: 0, longitude1: 0, latitude2: 0, longitude2: 0)
        precondition((zero["meters"] as? Double) == 0)
        let oneDegree = try HTMLAppAddressLookup.distance(
            latitude1: 0, longitude1: 0, latitude2: 0, longitude2: 1)
        guard let meters = oneDegree["meters"] as? Double else {
            fatalError("Distance returned no meters")
        }
        precondition(meters > 111_000 && meters < 112_000)
        precondition(oneDegree["kind"] as? String == "great_circle")
        do {
            _ = try HTMLAppAddressLookup.distance(
                latitude1: 95, longitude1: 0, latitude2: 0, longitude2: 0)
            fatalError("Out-of-range latitude was accepted")
        } catch HTMLAppAddressLookup.LookupError.invalidCoordinates {
            // Expected invalid coordinate rejection.
        }
        print("Offline location distance fixtures passed.")
    }
}
