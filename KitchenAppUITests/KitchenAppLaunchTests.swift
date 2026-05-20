import XCTest

// Measures cold-start launch performance. Reported in Xcode Organizer and Instruments.
final class KitchenAppLaunchTests: XCTestCase {

    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
