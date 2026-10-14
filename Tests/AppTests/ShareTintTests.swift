@testable import App
import SwiftUI
import XCTest

final class ShareTintTests: XCTestCase {
    func testHueAtBounds() {
        XCTAssertEqual(ShareTint.hue(forFillFraction: 0), ShareTint.emptyHue, accuracy: 0.0001)
        XCTAssertEqual(ShareTint.hue(forFillFraction: 1), ShareTint.fullHue, accuracy: 0.0001)
    }

    func testHueInMiddle() {
        let expected = ShareTint.emptyHue + (ShareTint.fullHue - ShareTint.emptyHue) * 0.5
        XCTAssertEqual(ShareTint.hue(forFillFraction: 0.5), expected, accuracy: 0.0001)
    }

    func testHueClamped() {
        XCTAssertEqual(ShareTint.hue(forFillFraction: -0.5), ShareTint.emptyHue, accuracy: 0.0001)
        XCTAssertEqual(ShareTint.hue(forFillFraction: 2.0), ShareTint.fullHue, accuracy: 0.0001)
    }

    func testColorClampsOutOfRange() {
        let over = ShareTint.color(for: 150, of: 100)
        let under = ShareTint.color(for: -10, of: 100)
        let fullColor = ShareTint.color(for: 100, of: 100)
        let emptyColor = ShareTint.color(for: 0, of: 100)

        XCTAssertNotEqual(over, ShareTint.neutral)
        XCTAssertNotEqual(under, ShareTint.neutral)
        XCTAssertEqual(ShareTint.hue(forFillFraction: 1), ShareTint.hue(forFillFraction: 1.5), accuracy: 0.0001)
        XCTAssertEqual(over.description, fullColor.description)
        XCTAssertEqual(under.description, emptyColor.description)
    }

    func testColorNeutralWhenInvalid() {
        XCTAssertEqual(ShareTint.color(for: nil, of: 100), ShareTint.neutral)
        XCTAssertEqual(ShareTint.color(for: 50, of: 0), ShareTint.neutral)
        XCTAssertEqual(ShareTint.color(for: Double.infinity, of: 100), ShareTint.neutral)
        XCTAssertEqual(ShareTint.color(for: 50, of: Double.infinity), ShareTint.neutral)
    }
}