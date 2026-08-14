import Foundation

public enum LocaleResolver {
    public static func tmdbLanguage(for locale: Locale = .current) -> String {
        let identifier = locale.identifier.lowercased().replacingOccurrences(of: "_", with: "-")
        if identifier.hasPrefix("vi") { return "vi-VN" }
        if identifier.hasPrefix("ja") { return "ja-JP" }
        if identifier.hasPrefix("ko") { return "ko-KR" }
        if locale.language.script?.identifier.lowercased() == "hant"
            || locale.region?.identifier.uppercased() == "TW"
            || locale.region?.identifier.uppercased() == "HK"
            || identifier.contains("hant")
            || identifier.hasPrefix("zh-tw")
            || identifier.hasPrefix("zh-hk") {
            return "zh-TW"
        }
        if identifier.hasPrefix("zh") { return "zh-CN" }
        return "en-US"
    }
}
