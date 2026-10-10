import AppKit
import SwiftUI

/// The approved copper palette follows the window's native light/dark appearance.
enum VaultStyle {
    static let background = color(0xFDFCFB, 0x242321)
    static let sidebar = color(0xF0EEEB, 0x292725)
    static let library = color(0xF8F7F5, 0x272624)
    static let field = color(0xF5F3F0, 0x302E2B)
    static let line = color(0xE4E0DB, 0x403C37)
    static let ink = color(0x302C28, 0xEEE9E2)
    static let copper = color(0x97562F, 0xE0AD86)
    static let selection = color(0xEDE0D3, 0x49392C)

    private static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

struct EntryEmblem: View {
    let symbol: String
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(VaultStyle.copper)
            .frame(width: size, height: size)
            .background(VaultStyle.field, in: RoundedRectangle(cornerRadius: size * 0.24))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(VaultStyle.line))
            .accessibilityHidden(true)
    }
}

extension View {
    func vaultField() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VaultStyle.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(VaultStyle.line))
    }
}
