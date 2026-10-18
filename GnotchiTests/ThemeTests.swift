import AppKit
import SwiftUI
import XCTest
@testable import Gnotchi

/// Aus Seam (Code-Audit 09.10., Q9): `NSColor(FamilyTheme.accent)` muss dynamisch bleiben.
/// Gnotchi: Pasta-Gold, hell #B07A2A, dunkel #E3B66A.
final class ThemeTests: XCTestCase {

    private func rgb(_ c: NSColor, _ name: NSAppearance.Name) -> [Int] {
        var out: [Int] = []
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let s = c.usingColorSpace(.sRGB)!
            out = [s.redComponent, s.greenComponent, s.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        return out
    }

    @MainActor
    func testGnotchiAccentStaysDynamicAsNSColor() {
        FamilyTheme.app = .gnotchi
        let c = NSColor(FamilyTheme.accent)
        XCTAssertEqual(rgb(c, .aqua), [0xB0, 0x7A, 0x2A])
        XCTAssertEqual(rgb(c, .darkAqua), [0xE3, 0xB6, 0x6A])
    }
}
