import XCTest

final class ExperiencePolicyTests: XCTestCase {
    private let base = ["entries": "old"]
    private let local = ["entries": "local edit"]
    private let cloud = ["entries": "cloud edit"]

    func testOneSidedEditsSyncWithoutAConflict() {
        let hash = HTMLAppSyncMergePolicy.fingerprint(base)
        XCTAssertEqual(HTMLAppSyncMergePolicy.decide(local: local, cloud: base, baseline: hash), .upload)
        XCTAssertEqual(HTMLAppSyncMergePolicy.decide(local: base, cloud: cloud, baseline: hash), .download)
    }

    func testConcurrentEditsAndFirstContactRequireReview() {
        XCTAssertEqual(HTMLAppSyncMergePolicy.decide(local: local, cloud: cloud,
            baseline: HTMLAppSyncMergePolicy.fingerprint(base)), .conflict)
        XCTAssertEqual(HTMLAppSyncMergePolicy.decide(local: local, cloud: cloud, baseline: nil), .conflict)
        XCTAssertEqual(HTMLAppSyncMergePolicy.decide(local: local, cloud: local, baseline: nil), .equal)
    }

    func testAnExplicitClearIsARealEdit() {
        let hash = HTMLAppSyncMergePolicy.fingerprint(base)
        XCTAssertEqual(HTMLAppSyncMergePolicy.decide(local: [:], cloud: base, baseline: hash), .upload)
        XCTAssertEqual(HTMLAppSyncMergePolicy.decide(local: base, cloud: [:], baseline: hash), .download)
        XCTAssertEqual(HTMLAppSyncMergePolicy.decide(local: local, cloud: [:], baseline: hash), .conflict)
    }

    func testFingerprintDoesNotDependOnDictionaryInsertionOrder() {
        XCTAssertEqual(HTMLAppSyncMergePolicy.fingerprint(["a": "1", "b": "2"]),
                       HTMLAppSyncMergePolicy.fingerprint(["b": "2", "a": "1"]))
    }

    func testFailedBuildNeverLooksReadyJustBecauseItHasAPreview() {
        XCTAssertEqual(ForgeBuildStage.current(phase: "Generating live preview", working: false, hasHTML: true, failed: true), .building)
        XCTAssertEqual(ForgeBuildStage.current(phase: "Ready to review", working: false, hasHTML: true), .ready)
        XCTAssertEqual(ForgeBuildStage.current(phase: "Checking device capabilities", working: true, hasHTML: false), .planning)
        XCTAssertEqual(ForgeBuildStage.current(phase: "Repairing confirmed app error", working: true, hasHTML: true), .checking)
    }

    func testTrialMarkerIsOnlyInTheTrialDocument() {
        for starter in ForgeStarterApp.all {
            XCTAssertFalse(starter.html.contains("window.__HTMLAPP_STARTER_PREVIEW__=true"))
            XCTAssertTrue(HTMLAppTrialDocument.prepare(starter.html).contains("window.__HTMLAPP_STARTER_PREVIEW__=true"))
            XCTAssertFalse(starter.html.contains("__SCRIPT__"))
            XCTAssertFalse(starter.html.contains("__BODY__"))
        }
    }
}
