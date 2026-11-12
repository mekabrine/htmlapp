import XCTest

final class ForgeFixerTests: XCTestCase {
    func testExactAliasesAndIdempotence() {
        let html = "<html><head></head><body><script>HTMLAppNative.vision.detectFace(image);</script></body></html>"
        let fixed = ForgeLocalFixers.repair(html)
        XCTAssertTrue(fixed.contains("vision.detectFaces(image)"))
        XCTAssertEqual(ForgeLocalFixers.repair(fixed), fixed)
        XCTAssertEqual(ForgeLocalFixers.repair("<p>HTMLAppNative.vision.detectFace(image)</p>"), "<p>HTMLAppNative.vision.detectFace(image)</p>")
    }

    func testVisionAdapterAndUnsupportedAPI() {
        let html = "<html><head></head><body><script>new FaceDetector()</script></body></html>"
        let fixed = ForgeLocalFixers.repair(html)
        XCTAssertTrue(fixed.contains("data-htmlapp-vision-fixer"))
        XCTAssertEqual(ForgeLocalFixers.repair(fixed), fixed)
        XCTAssertFalse(HTMLAppBridgeLint.warnings(in: fixed).contains { $0.hasPrefix("Capability fixer:") })
        XCTAssertTrue(HTMLAppBridgeLint.warnings(in: "HTMLAppNative.vision.inventedAPI()").contains { ForgeLocalFixers.blocking($0) })
        XCTAssertTrue(HTMLAppBridgeLint.warnings(in: "HTMLAppNative.vision.detectFaces(image)").isEmpty)
    }
}
