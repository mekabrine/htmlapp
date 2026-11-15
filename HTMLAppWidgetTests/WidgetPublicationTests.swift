import XCTest

final class WidgetPublicationTests: XCTestCase {
    func testPublicationNotificationSeesCommittedSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HTMLAppWidgetRepository(directory: directory)
        var definition = HTMLAppWidgetDefinition.placeholder(id: "publication-test")
        definition.snapshot.value = "Updated without restarting"
        let expected = definition.snapshot.value
        let publication = expectation(description: "Verified publication announces a refresh")
        let observer = NotificationCenter.default.addObserver(forName: HTMLAppWidgetStore.committed, object: nil, queue: nil) { _ in
            // Reenter from a new reader: the writer must have released its
            // file coordination before requesting a timeline update.
            let reader = HTMLAppWidgetRepository(directory: directory)
            XCTAssertEqual(try? reader.all().first?.snapshot.value, expected)
            publication.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        _ = try repository.save(definition)
        wait(for: [publication], timeout: 1)
    }

    func testRejectedMutationDoesNotAnnouncePublication() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HTMLAppWidgetRepository(directory: directory)
        let observer = NotificationCenter.default.addObserver(forName: HTMLAppWidgetStore.committed, object: nil, queue: nil) { _ in
            XCTFail("A rejected transaction must not request a widget reload")
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        XCTAssertThrowsError(try repository.mutate { _ in throw CocoaError(.fileWriteUnknown) })
    }
}
