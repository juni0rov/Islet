import Foundation
import Testing
#if !ISLET_LOCAL_TESTS
@testable import Islet
#endif

@Suite struct ThemeTests {
    @Test func tokensMatchSpecTable() {
        #expect(ThemeTokens.obsidian.base.hexString == "#202122")
        #expect(ThemeTokens.obsidian.panel.hexString == "#414244")
        #expect(ThemeTokens.obsidian.stroke.hexString == "#707173")
        #expect(ThemeTokens.pearl.base.hexString == "#D7D3CB")
        #expect(ThemeTokens.pearl.panel.hexString == "#F0EEE8")
        #expect(ThemeTokens.pearl.stroke.hexString == "#FFFFFF")
        #expect(ThemeTokens.adaptiveFallback.base.hexString == "#384B4B")
        #expect(ThemeTokens.adaptiveFallback.panel.hexString == "#637576")
        #expect(ThemeTokens.adaptiveFallback.stroke.hexString == "#91A2A0")
    }

    @Test func contrastRatiosMatchSpec() {
        func r(_ a: String, _ b: String) -> Double { RGB.contrast(RGB(hex: a), RGB(hex: b)) }
        #expect(abs(r("#F6F6F5", "#414244") - 9.30) < 0.05)
        #expect(abs(r("#CBCBCD", "#414244") - 6.21) < 0.05)
        #expect(abs(r("#252522", "#F0EEE8") - 13.25) < 0.05)
        #expect(abs(r("#575650", "#F0EEE8") - 6.35) < 0.05)
        #expect(abs(r("#FFFFFF", "#637576") - 4.84) < 0.05)
        #expect(abs(r("#E8EFEE", "#516364") - 5.43) < 0.1)
    }

    @Test(arguments: [ThemeTokens.obsidian, .pearl, .adaptiveFallback])
    func everyThemePassesThresholdsOnPanel(tokens: ThemeTokens) {
        #expect(Contrast.audit(tokens).isEmpty)
    }

    /// Text on the translucent base tint over black and white backdrops.
    @Test(arguments: [ThemeTokens.obsidian, .pearl, .adaptiveFallback])
    func textReadableOnGlassOverAnyBackdrop(tokens: ThemeTokens) {
        for backdrop in [RGB.black, RGB.white, RGB(hex: "#7F7F7F")] {
            let surface = backdrop.mixed(with: tokens.base, amount: tokens.glassOpacity)
            #expect(RGB.contrast(tokens.textPrimary, surface) >= Contrast.textMinimum)
            #expect(RGB.contrast(tokens.textSecondary, surface) >= Contrast.textMinimum)
        }
    }

    @Test(arguments: ["#FF0000", "#00FF00", "#0000FF", "#FFFFFF", "#000000", "#E0C080", "#8090A0"])
    func adaptiveFromAnySeedPassesThresholds(hex: String) {
        let t = ThemeTokens.adaptive(seed: RGB(hex: hex))
        #expect(Contrast.audit(t).isEmpty, "seed \(hex)")
    }

    /// Text on the island body and its inner cards.
    @Test(arguments: [ThemeTokens.obsidian, .pearl, .adaptiveFallback])
    func islandBodyAndCardsReadable(tokens: ThemeTokens) {
        for bg in [tokens.islandBody, tokens.card] {
            #expect(RGB.contrast(tokens.islandPrimary, bg) >= Contrast.textMinimum)
            #expect(RGB.contrast(tokens.islandSecondary, bg) >= Contrast.textMinimum)
        }
    }

    @Test func hslRoundTrip() {
        let c = RGB(hex: "#637576")
        let (h, s, l) = c.hsl
        #expect(RGB(h: h, s: s, l: l).hexString == "#637576")
    }
}

@Suite struct LanguageTests {
    let available = ["en", "ru"]

    @Test func exactAndCompatibleMatches() {
        #expect(LanguageResolver.resolve(preferred: ["ru-RU"], available: available) == "ru")
        #expect(LanguageResolver.resolve(preferred: ["ru-KZ", "en"], available: available) == "ru")
        #expect(LanguageResolver.resolve(preferred: ["en-AU"], available: available) == "en")
    }

    @Test func walksPreferenceOrderThenFallsBackToEnglish() {
        #expect(LanguageResolver.resolve(preferred: ["fr-FR", "ru"], available: available) == "ru")
        #expect(LanguageResolver.resolve(preferred: ["fr-FR", "de"], available: available) == "en")
        #expect(LanguageResolver.resolve(preferred: [], available: available) == "en")
    }

    @Test func neverSwapsChineseScripts() {
        let zh = ["en", "zh-Hans"]
        #expect(LanguageResolver.resolve(preferred: ["zh-Hant-TW"], available: zh) == "en")
        #expect(LanguageResolver.resolve(preferred: ["zh-TW"], available: zh) == "en")
        #expect(LanguageResolver.resolve(preferred: ["zh-CN"], available: zh) == "zh-Hans")
        #expect(LanguageResolver.resolve(preferred: ["zh-Hans-SG"], available: zh) == "zh-Hans")
    }

    @Test func normalizesUnavailableStoredValueToSystem() {
        #expect(LanguageResolver.normalize(stored: "ja", available: available) == "system")
        #expect(LanguageResolver.normalize(stored: nil, available: available) == "system")
        #expect(LanguageResolver.normalize(stored: "ru", available: available) == "ru")
    }

    @Test(arguments: [(1, PluralCategory.one), (2, .few), (5, .many), (11, .many), (21, .one), (22, .few), (12, .many), (111, .many)])
    func russianPluralCategories(n: Int, expected: PluralCategory) {
        #expect(PluralCategory.category(for: n, language: "ru") == expected)
    }

    @Test(arguments: [(0, PluralCategory.zero), (1, .one), (2, .two), (3, .few), (11, .many), (100, .other)])
    func arabicPluralCategories(n: Int, expected: PluralCategory) {
        #expect(PluralCategory.category(for: n, language: "ar") == expected)
    }

    @Test func russianFileForms() {
        let c = StringCatalog.shared
        let ru = Locale(identifier: "ru")
        #expect(c.plural("shelf.count", count: 1, language: "ru", locale: ru) == "1 файл")
        #expect(c.plural("shelf.count", count: 2, language: "ru", locale: ru) == "2 файла")
        #expect(c.plural("shelf.count", count: 5, language: "ru", locale: ru) == "5 файлов")
        #expect(c.plural("shelf.count", count: 11, language: "ru", locale: ru) == "11 файлов")
        #expect(c.plural("shelf.count", count: 21, language: "ru", locale: ru) == "21 файл")
    }

    @Test func fallbackChainReachesEnglishAndKey() {
        let c = StringCatalog.shared
        #expect(c.string("menu.quit", language: "ru-KZ") == "Выйти из Islet")
        #expect(c.string("menu.quit", language: "ja") == "Quit Islet")
        #expect(c.string("no.such.key", language: "ru") == "no.such.key")
    }

    @Test func catalogIsCompleteForShippedLanguages() {
        let c = StringCatalog.shared
        #expect(Set(c.completeLanguages) == ["en", "ru"])
        for (key, perLang) in c.entries {
            if case .plural(let forms)? = perLang["ru"] {
                for cat in [PluralCategory.one, .few, .many, .other] {
                    #expect(forms[cat] != nil, "ru plural \(key) missing \(cat)")
                }
            }
        }
    }

    @Test func explicitChoiceSurvivesRelaunchAndBeatsSystem() async {
        await MainActor.run {
            let defaults = UserDefaults(suiteName: "islet.tests.\(UUID().uuidString)")!
            let store = LanguageStore(defaults: defaults, preferred: { ["en-US"] })
            #expect(store.resolved == "en")
            store.select("ru")
            #expect(store.resolved == "ru")
            #expect(store.t("menu.quit") == "Выйти из Islet")
            let relaunched = LanguageStore(defaults: defaults, preferred: { ["en-US"] })
            #expect(relaunched.selection == "ru")
            #expect(relaunched.resolved == "ru")
            relaunched.select("system")
            #expect(relaunched.resolved == "en")
        }
    }
}
