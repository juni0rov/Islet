import AppKit
import SwiftUI

/// Pure matching of system preferences against the app's available languages.
enum LanguageResolver {
    static let systemValue = "system"
    static let baseLanguage = "en"

    /// Picks the best available language for an ordered list of preferences.
    /// Exact tag first, then same language with a compatible script; a
    /// different script (zh-Hant vs zh-Hans) never matches. Falls back to en.
    static func resolve(preferred: [String], available: [String]) -> String {
        for pref in preferred {
            if let match = match(pref, in: available) { return match }
        }
        return available.contains(baseLanguage) ? baseLanguage : (available.first ?? baseLanguage)
    }

    static func match(_ pref: String, in available: [String]) -> String? {
        let p = LanguageTag(pref)
        if let exact = available.first(where: { $0.caseInsensitiveCompare(pref) == .orderedSame }) {
            return exact
        }
        let compatible = available.filter {
            let a = LanguageTag($0)
            return a.language == p.language && a.effectiveScript == p.effectiveScript
        }
        // Prefer the same region, then the least specific tag.
        if let sameRegion = compatible.first(where: { LanguageTag($0).region == p.region && p.region != nil }) {
            return sameRegion
        }
        return compatible.sorted {
            let r0 = LanguageTag($0).region == nil ? 0 : 1
            let r1 = LanguageTag($1).region == nil ? 0 : 1
            return r0 != r1 ? r0 < r1 : $0 < $1
        }.first
    }

    /// Normalises a stored value: unknown / unavailable languages become system.
    static func normalize(stored: String?, available: [String]) -> String {
        guard let stored, stored != systemValue else { return systemValue }
        return available.contains(stored) ? stored : systemValue
    }
}

/// Publishes the selected language, writing direction and region format.
@MainActor
final class LanguageStore: ObservableObject {
    static let defaultsKey = "islet.language"

    @Published private(set) var selection: String
    @Published private(set) var resolved: String
    @Published private(set) var layoutDirection: LayoutDirection = .leftToRight
    @Published private(set) var locale: Locale = .current

    let available: [String]
    private let defaults: UserDefaults
    private let catalog: StringCatalog
    private let preferred: () -> [String]
    private var observers: [NSObjectProtocol] = []
    private let pseudo = ProcessInfo.processInfo.environment["ISLET_PSEUDO"] == "1"
    private let forcedRTL = ProcessInfo.processInfo.environment["ISLET_RTL"] == "1"

    init(defaults: UserDefaults = .standard,
         catalog: StringCatalog = .shared,
         preferred: @escaping () -> [String] = { Locale.preferredLanguages }) {
        self.defaults = defaults
        self.catalog = catalog
        self.preferred = preferred
        self.available = catalog.completeLanguages
        let stored = defaults.string(forKey: Self.defaultsKey)
        let normalized = LanguageResolver.normalize(stored: stored, available: catalog.completeLanguages)
        selection = normalized
        resolved = LanguageResolver.baseLanguage
        if stored != normalized { defaults.set(normalized, forKey: Self.defaultsKey) }
        apply()
    }

    func startObservingSystem() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshSystem() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshSystem() }
        })
    }

    func select(_ value: String) {
        let normalized = LanguageResolver.normalize(stored: value, available: available)
        selection = normalized
        defaults.set(normalized, forKey: Self.defaultsKey)
        apply()
    }

    /// Re-reads system preferences; a manual choice stays in force.
    func refreshSystem() {
        guard selection == LanguageResolver.systemValue else { return }
        apply()
    }

    private func apply() {
        let lang = selection == LanguageResolver.systemValue
            ? LanguageResolver.resolve(preferred: preferred(), available: available)
            : selection
        if lang != resolved { resolved = lang }
        // Keep the user's region format, but take the language of the UI.
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(identifier: lang)
        let newLocale = Locale(components: components)
        if newLocale.identifier != locale.identifier { locale = newLocale }
        let rtl = forcedRTL || Locale.Language(identifier: lang).characterDirection == .rightToLeft
        let dir: LayoutDirection = rtl ? .rightToLeft : .leftToRight
        if dir != layoutDirection { layoutDirection = dir }
    }

    // MARK: Lookup

    func t(_ key: String) -> String {
        decorate(catalog.string(key, language: resolved))
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        decorate(String(format: catalog.string(key, language: resolved), locale: locale, arguments: args))
    }

    func plural(_ key: String, _ count: Int) -> String {
        decorate(catalog.plural(key, count: count, language: resolved, locale: locale))
    }

    /// Autonym of a language, e.g. "Русский".
    func autonym(_ tag: String) -> String {
        let name = Locale(identifier: tag).localizedString(forIdentifier: tag) ?? tag
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Pseudo-localisation (ISLET_PSEUDO=1): strings grow by ~40%.
    private func decorate(_ s: String) -> String {
        guard pseudo else { return s }
        let extra = max(2, Int(Double(s.count) * 0.4))
        return "⟦" + s + String(repeating: "~", count: extra - 2) + "⟧"
    }
}

/// Wraps embedded file names / paths so they keep their own direction.
func isolated(_ s: String) -> String { "\u{2068}" + s + "\u{2069}" }
