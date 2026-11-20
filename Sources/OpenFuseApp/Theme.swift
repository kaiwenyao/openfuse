import AppKit
import SwiftUI

/// 用户可选的外观。默认明亮；选择写入 UserDefaults，重启后保留。
enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    static let storageKey = "openfuse.appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "明亮"
        case .dark: return "深色"
        case .system: return "跟随系统"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }

    /// 已保存的外观；没有记录时使用明亮。
    static var stored: AppTheme {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let theme = AppTheme(rawValue: raw)
        else { return .light }
        return theme
    }

    static func persist(_ theme: AppTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: storageKey)
        theme.apply()
    }

    /// AppKit 层的外观。SwiftUI 侧由 `.preferredColorScheme` 同步。
    func apply() {
        NSApplication.shared.appearance = appearance
    }
}

/// 主题色板。每个色值都带明亮/深色两份，随当前外观解析，
/// 因此现有 `Theme.xxx` 静态引用无需感知外观即可正确换肤。
enum Theme {
    static let background = palette(light: 0xF5F6F8, dark: 0x0B0D11)
    static let backgroundAlt = palette(light: 0xE9EEF6, dark: 0x0E1219)
    static let panel = palette(light: 0xFFFFFF, dark: 0x15181E)
    static let elevated = palette(light: 0xE8EDF3, dark: 0x1D2128)
    static let accent = palette(light: 0x0B6FD1, dark: 0x5CC7FA)
    static let warm = palette(light: 0xB26A00, dark: 0xFAB840)
    static let text = palette(light: 0x111820, dark: 0xEDF2FA)
    static let secondary = palette(light: 0x5C6674, dark: 0x94A0B0)
    static let stroke = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance)
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.10)
    })

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func palette(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(openFuseHex: isDark(appearance) ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(openFuseHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
