import SwiftUI
import XCTest
@testable import CryptaDesktop

final class TagFlowLayoutTests: XCTestCase {
    func testTagsStayAdjacentAndWrapWhenWidthShrinks() {
        let sizes = [CGSize(width: 40, height: 20), CGSize(width: 50, height: 20), CGSize(width: 30, height: 28)]
        let wide = TagFlowLayout.arrange(sizes, width: 400)
        XCTAssertEqual(wide.positions, [CGPoint(x: 0, y: 0), CGPoint(x: 46, y: 0), CGPoint(x: 102, y: 0)])
        XCTAssertEqual(wide.size, CGSize(width: 132, height: 28))
        let narrow = TagFlowLayout.arrange(sizes, width: 100)
        XCTAssertEqual(narrow.positions, [CGPoint(x: 0, y: 0), CGPoint(x: 46, y: 0), CGPoint(x: 0, y: 26)])
        XCTAssertEqual(narrow.size, CGSize(width: 96, height: 54))
    }

    func testEmptyAndExactWidthRows() {
        XCTAssertEqual(TagFlowLayout.arrange([], width: 100).size, .zero)
        let sizes = [CGSize(width: 100, height: 40), CGSize(width: 40, height: 20)]
        let result = TagFlowLayout.arrange(sizes, width: 100)
        XCTAssertEqual(result.positions, [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 46)])
        XCTAssertEqual(result.size, CGSize(width: 100, height: 66))
    }
}
