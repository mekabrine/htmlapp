import XCTest
import Foundation

final class SystemControlTests: XCTestCase {
    func testChartsRejectNonFiniteAndOversizedData() {
        var node = HTMLAppWidgetElement(type: "lineChart")
        node.samples = [0, 0.5, 1]
        var count = 0
        XCTAssertTrue(node.isValid(count: &count))
        node.samples = [0, .nan]
        count = 0
        XCTAssertFalse(node.isValid(count: &count))
        node.samples = Array(repeating: 0.5, count: 65)
        count = 0
        XCTAssertFalse(node.isValid(count: &count))
        node = HTMLAppWidgetElement(type: "route")
        node.points = [.init(x: 0, y: 0), .init(x: 1, y: 1)]
        count = 0
        XCTAssertTrue(node.isValid(count: &count))
        node.points = [.init(x: 0, y: 0), .init(x: 1.01, y: 1)]
        count = 0
        XCTAssertFalse(node.isValid(count: &count))
    }

    func testRouteMarkerUsesDistanceInsteadOfPointCount() {
        let points = [HTMLAppWidgetPoint(x: 0, y: 0), .init(x: 0.1, y: 0), .init(x: 1, y: 0)]
        let middle = HTMLAppPolyline.location(at: 0.5, points: points)
        XCTAssertEqual(middle.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(middle.y, 0)
        XCTAssertEqual(HTMLAppPolyline.location(at: 1, points: points).x, 1)
        XCTAssertEqual(HTMLAppPolyline.location(at: 1, points: points, closed: true).x, 0)
    }

    func testStateValidationRejectsNonBooleanToggleValues() throws {
        let control = HTMLAppSystemControl(appID: "project", appName: "Project", controlID: "quiet",
            title: "Quiet", systemSymbol: "moon", type: "toggle", stateKey: "quiet")
        var document = HTMLAppSystemControlDocument()
        document.controls = [control]
        document.values = ["project": ["quiet": .boolean(true)], "other": ["quiet": .text("unrelated")]]
        XCTAssertNoThrow(try HTMLAppSystemControlStore.validateValues(appID: "project", in: document))
        document.values["project"]?["quiet"] = .text("true")
        XCTAssertThrowsError(try HTMLAppSystemControlStore.validateValues(appID: "project", in: document))
    }

    func testRepositoryPreservesOtherProjectsAndRollsBackFailedMutation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HTMLAppSystemControlRepository(directory: directory)
        try repository.mutate { $0.values = ["a": ["flag": .boolean(true)], "b": ["count": .number(4)]] }
        try repository.mutate { $0.values["a"]?["flag"] = .boolean(false) }
        XCTAssertEqual(try repository.read().values["b"]?["count"], .number(4))
        XCTAssertThrowsError(try repository.mutate { document in
            document.values.removeAll()
            throw HTMLAppSystemControlError.invalid
        })
        XCTAssertEqual(try repository.read().values["b"]?["count"], .number(4))
        let damaged = Data("invalid JSON".utf8)
        try damaged.write(to: repository.file)
        XCTAssertThrowsError(try repository.mutate { $0.values = [:] })
        XCTAssertEqual(try Data(contentsOf: repository.file), damaged)
    }

    func testScalarTypesStayDistinctAcrossEncoding() throws {
        let values: [String: HTMLAppControlValue] = ["flag": .boolean(false), "count": .number(1), "title": .text("1")]
        let restored = try JSONDecoder().decode([String: HTMLAppControlValue].self, from: JSONEncoder().encode(values))
        XCTAssertEqual(restored, values)
    }
}
