import XCTest

/// Real simulator smoke tests for routing into the root-owned import screen.
/// These tests inject documents *at the app boundary*. A physical-device
/// Files/Share-sheet test is still required for the OS handoff itself.
final class HTMLAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ argument: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboardingComplete", "YES"
        ]
        if let argument { app.launchArguments.append(argument) }
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 25))
        return app
    }

    func testLibraryStarts() throws {
        let app = launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    }

    func testExternalHTMLLaunchOpensImportScreen() throws {
        let app = launch("-HTMLAppUITestExternalImport")
        XCTAssertTrue(
            app.navigationBars["Import HTML"].waitForExistence(timeout: 30),
            "An external document queued during startup must present Import HTML."
        )
        XCTAssertTrue(app.buttons["Install as New HTML App"].exists)
    }

    func testSharedInboxOpensImportScreen() throws {
        let app = launch("-HTMLAppUITestSharedInbox")
        XCTAssertTrue(
            app.navigationBars["Import HTML"].waitForExistence(timeout: 30),
            "An App Group shared document must present the Import screen."
        )
        XCTAssertTrue(app.buttons["Install as New HTML App"].exists)
    }
}
