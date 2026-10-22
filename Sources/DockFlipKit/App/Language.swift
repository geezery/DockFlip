import Foundation

/// The languages DockFlip speaks, and the choice made in its menu.
///
/// By default DockFlip follows macOS (System Settings → General → Language &
/// Region, or per app). The menu bar menu can pin a language for DockFlip only; it
/// is stored as DockFlip's own `AppleLanguages` and applies after a restart.
/// Language names are shown in their own language with the English name beside
/// them, so English can always be found again whatever language is showing.
enum AppLanguage {
    struct Option {
        let code: String
        /// The name in the language itself: "Suomi".
        let nativeName: String
        /// The name in English: "Finnish".
        let englishName: String
    }

    static let all: [Option] = [
        Option(code: "en", nativeName: "English", englishName: "English"),
        Option(code: "fi", nativeName: "Suomi", englishName: "Finnish"),
        Option(code: "sv", nativeName: "Svenska", englishName: "Swedish"),
        Option(code: "da", nativeName: "Dansk", englishName: "Danish"),
        Option(code: "nb", nativeName: "Norsk bokmål", englishName: "Norwegian"),
        Option(code: "de", nativeName: "Deutsch", englishName: "German"),
        Option(code: "fr", nativeName: "Français", englishName: "French"),
        Option(code: "es", nativeName: "Español", englishName: "Spanish"),
        Option(code: "it", nativeName: "Italiano", englishName: "Italian"),
        Option(code: "pt-BR", nativeName: "Português (Brasil)", englishName: "Portuguese (Brazil)"),
        Option(code: "nl", nativeName: "Nederlands", englishName: "Dutch"),
        Option(code: "pl", nativeName: "Polski", englishName: "Polish"),
        Option(code: "ja", nativeName: "日本語", englishName: "Japanese"),
        Option(code: "ko", nativeName: "한국어", englishName: "Korean"),
        Option(code: "zh-Hans", nativeName: "简体中文", englishName: "Chinese (Simplified)")
    ]

    private static let key = "AppleLanguages"

    /// The language pinned in DockFlip's menu, or nil when DockFlip follows macOS.
    /// Read from DockFlip's own defaults only — the system-wide list always exists.
    static var chosen: String? {
        guard let domain = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: domain)?[key] as? [String] else { return nil }
        return languages.first
    }

    /// Pins `code` for DockFlip, or follows macOS again with nil. Takes effect on restart.
    static func choose(_ code: String?) {
        if let code {
            UserDefaults.standard.set([code], forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// The language DockFlip is showing now.
    static var current: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }
}

/// Localized string with the English text as its key. The English text is also
/// the fallback, so a missing translation shows English, never a key.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
