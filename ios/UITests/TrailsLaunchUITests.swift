import XCTest

final class TrailsLaunchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launchEnvironment["TRAILS_UI_TESTING"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testLaunchShowsMainTabRoot() throws {
        XCTAssertTrue(
            app.otherElements["main.tab.view"].waitForExistence(timeout: 20),
            "Expected the main tab root to be visible after launching in UI-test mode."
        )
    }
}
