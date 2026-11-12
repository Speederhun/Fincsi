import XCTest
@testable import FincsiKit

final class SmokeTests: XCTestCase {
    func testName() {
        XCTAssertEqual(FincsiInfo.name, "Fincsi")
    }
}
