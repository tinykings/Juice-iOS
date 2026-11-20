import SwiftUI
import UIKit

// The Pocket Journal palette (the website's DESIGN.md): Parchment in light mode,
// Charcoal in dark, one honey-gold accent.
enum Palette {
    private static func dynamic(light: UInt32, dark: UInt32, darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light)
        })
    }

    static let background = dynamic(light: 0xF4F1EA, dark: 0x0F0E0C)
    static let foreground = dynamic(light: 0x1A1712, dark: 0xF3F0EA)
    static let card = dynamic(light: 0xFFFCF5, dark: 0x191713)
    static let taskSurface = dynamic(light: 0xFFFCF5, dark: 0x1F1C18)
    static let inset = dynamic(light: 0xECE6DA, dark: 0x26231F)
    static let muted = dynamic(light: 0x6B6357, dark: 0xA8A29A)
    static let border = dynamic(light: 0xD6CDBD, dark: 0x2A2723)
    static let accent = dynamic(light: 0x8F5C12, dark: 0xD7A93A)
    static let accentSurface = dynamic(light: 0xF3E6CC, dark: 0x2B2414)
    static let red = dynamic(light: 0xC81E1E, dark: 0xFF6B6B)
    static let event = dynamic(light: 0x2F5F96, dark: 0x7FA7D9)
    static let checkbox = dynamic(light: 0xB9AE9C, dark: 0x5A554E)
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "theme"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Parchment"
        case .dark: "Charcoal"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension Font {
    static let taskTitle = Font.system(size: 17, weight: .semibold)
    static let taskNote = Font.system(size: 15)
    static let meta = Font.system(size: 13, weight: .medium)
    static let groupHeader = Font.system(size: 13, weight: .bold)
}
