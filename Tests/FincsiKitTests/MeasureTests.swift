import XCTest
@testable import FincsiKit

final class MeasureTests: XCTestCase {
    func testGrams() {
        let m = MeasureParser.parse("200g")
        XCTAssertEqual(m.amount ?? 0, 200, accuracy: 0.01)
        XCTAssertEqual(m.unit, "g")
    }

    func testTablespoonAndFraction() {
        let m = MeasureParser.parse("1/2 tbsp")
        XCTAssertEqual(m.amount ?? 0, 0.5, accuracy: 0.01)
        XCTAssertEqual(m.unit, "ek")
    }

    func testCupsToDeciliters() {
        let m = MeasureParser.parse("2 cups")
        XCTAssertEqual(m.amount ?? 0, 4.8, accuracy: 0.01)
        XCTAssertEqual(m.unit, "dl")
    }

    func testEmptyAndTasteDoNotCrash() {
        XCTAssertNil(MeasureParser.parse("").amount)
        _ = MeasureParser.parse("to taste")
        _ = MeasureParser.parse("a bit of this")
    }

    func testTimerExtraction() {
        XCTAssertEqual(TimerExtractor.minutes(in: "Süsd 20 percig."), 20)
        XCTAssertNil(TimerExtractor.minutes(in: "Keverd össze."))
    }

    func testInstructionSteps() {
        let steps = InstructionParser.steps(from: "Step 1\r\nChop the onion.\r\nFry for 5 minutes.")
        XCTAssertFalse(steps.isEmpty)
        XCTAssertFalse(steps.contains { $0.text.isEmpty })
    }

    func testFormatterNeverEmptyForAmount() {
        XCTAssertFalse(QuantityFormatter.format(amount: 1.5, unit: "dl").isEmpty)
        XCTAssertEqual(QuantityFormatter.format(amount: nil, unit: ""), "")
    }
}
