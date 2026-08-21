import XCTest

final class CalculatorTests: XCTestCase {
    func testThousandsSeparators() {
        XCTAssertEqual(Calculator.evaluate("1,000+1"), "1001")
        XCTAssertEqual(Calculator.evaluate("1，000+2"), "1002")
        XCTAssertEqual(Calculator.evaluate("1,000,000.5+0.5"), "1000001")
        XCTAssertNil(Calculator.evaluate("1,2+3"))
    }

    func testIncompleteTrailingOperatorUsesCompletedPrefix() {
        XCTAssertEqual(Calculator.evaluate("1+1+"), "2")
        XCTAssertEqual(Calculator.evaluate("10 / 2 *"), "5")
    }

    func testCommonCalculatorSyntax() {
        XCTAssertEqual(Calculator.evaluate("2^3"), "8")
        XCTAssertEqual(Calculator.evaluate("6×7"), "42")
        XCTAssertEqual(Calculator.evaluate("8÷4"), "2")
        XCTAssertEqual(Calculator.evaluate("(2+3"), "5")
    }

    func testNonExpressionDoesNotBecomeCalculatorResult() {
        XCTAssertNil(Calculator.evaluate("Knot"))
        XCTAssertNil(Calculator.evaluate("1000"))
    }
}
