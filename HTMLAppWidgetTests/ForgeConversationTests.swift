import XCTest
import Foundation

final class ForgeConversationTests: XCTestCase {
    func testAppendAndMergePreserveHistoryAndIdentity() throws {
        let id = "test-" + UUID().uuidString
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp/ConversationLogs/" + id + ".jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        ForgeConversationLog.append(id, kind: "user", text: "Make the title blue")
        ForgeConversationLog.append(id, kind: "assistant", text: "Changed the title color in CSS")
        let original = ForgeConversationLog.entries(id)
        XCTAssertEqual(original.count, 2)
        ForgeConversationLog.merge(id, incoming: original)
        XCTAssertEqual(ForgeConversationLog.entries(id).map(\.id), original.map(\.id))
        ForgeConversationLog.append(id, kind: "revert", text: "User reverted 1 edit")
        XCTAssertEqual(ForgeConversationLog.entries(id).count, 3)
        XCTAssertTrue(ForgeConversationLog.context(id).contains("User reverted 1 edit"))
        XCTAssertEqual(ForgeConversationLog.entries(id).count, 3, "Reading bounded AI context must not prune durable history")
    }

    func testAttachmentTargetsFollowVisibleCentersOnPhoneAndTablet() {
        for width in [CGFloat(320), CGFloat(393), CGFloat(768)] {
            XCTAssertEqual(ForgeAttachmentTarget.hit(CGPoint(x: width / 2 - 100, y: 52), width: width), .camera)
            XCTAssertEqual(ForgeAttachmentTarget.hit(CGPoint(x: width / 2, y: 52), width: width), .photos)
            XCTAssertEqual(ForgeAttachmentTarget.hit(CGPoint(x: width / 2 + 100, y: 52), width: width), .files)
            XCTAssertNil(ForgeAttachmentTarget.hit(CGPoint(x: width / 2, y: 180), width: width))
            XCTAssertNil(ForgeAttachmentTarget.hit(CGPoint(x: width / 2 - 50, y: 52), width: width))
        }
    }
}
