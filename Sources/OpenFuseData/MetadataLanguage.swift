import Foundation

/// Effective metadata language for this app. macOS stores a per-app language
/// override in the app's AppleLanguages defaults; otherwise use the system
/// preferred-language order. Simplified/Traditional Chinese are kept distinct.
public struct MetadataLanguage: Hashable, Sendable {
    public let identifier: String
    public let wikipedia: [String]
    public let tmdb: String
    public let isChinese: Bool
    public let isTraditionalChinese: Bool

    public static func current(defaults: UserDefaults = .standard) -> MetadataLanguage {
        let override = defaults.array(forKey: "AppleLanguages") as? [String]
        let preferred = override?.first ?? Locale.preferredLanguages.first ?? "en"
        return resolve(preferred)
    }

    public static func resolve(_ raw: String) -> MetadataLanguage {
        let normalized = raw.replacingOccurrences(of: "_", with: "-")
        let lower = normalized.lowercased()
        if lower.hasPrefix("zh") {
            let traditional = lower.contains("hant") || lower.contains("tw") || lower.contains("hk") || lower.contains("mo")
            return MetadataLanguage(
                identifier: traditional ? "zh-Hant" : "zh-Hans",
                wikipedia: ["zh", "en"],
                tmdb: traditional ? "zh-TW" : "zh-CN",
                isChinese: true,
                isTraditionalChinese: traditional
            )
        }
        if lower.hasPrefix("ja") {
            return MetadataLanguage(identifier: "ja", wikipedia: ["ja", "en"], tmdb: "ja-JP", isChinese: false, isTraditionalChinese: false)
        }
        if lower.hasPrefix("ko") {
            return MetadataLanguage(identifier: "ko", wikipedia: ["ko", "en"], tmdb: "ko-KR", isChinese: false, isTraditionalChinese: false)
        }
        if lower.hasPrefix("fr") {
            return MetadataLanguage(identifier: "fr", wikipedia: ["fr", "en"], tmdb: "fr-FR", isChinese: false, isTraditionalChinese: false)
        }
        if lower.hasPrefix("de") {
            return MetadataLanguage(identifier: "de", wikipedia: ["de", "en"], tmdb: "de-DE", isChinese: false, isTraditionalChinese: false)
        }
        if lower.hasPrefix("es") {
            return MetadataLanguage(identifier: "es", wikipedia: ["es", "en"], tmdb: "es-ES", isChinese: false, isTraditionalChinese: false)
        }
        let base = lower.split(separator: "-").first.map(String.init) ?? "en"
        return MetadataLanguage(identifier: base, wikipedia: [base, "en"], tmdb: "\(base)-\(base.uppercased())", isChinese: false, isTraditionalChinese: false)
    }

    public func convert(_ text: String) -> String {
        guard isTraditionalChinese else { return text }
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, "Hans-Hant" as CFString, false)
        return mutable as String
    }

    public func convertToHans(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, "Hant-Hans" as CFString, false)
        return mutable as String
    }

    /// Converts a Chinese title into the user's script. Other languages are
    /// left untouched.
    public func localizedTitle(_ text: String) -> String {
        guard isChinese else { return text }
        return isTraditionalChinese ? convert(text) : convertToHans(text)
    }

    public func localized(_ simplified: String?, traditional: String? = nil, english: String?) -> String? {
        if isTraditionalChinese {
            return traditional ?? simplified.map(convert) ?? english
        }
        if isChinese {
            return simplified ?? english
        }
        return english
    }
}
