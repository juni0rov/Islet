import Foundation

/// CLDR plural categories for the languages Islet ships or tests.
enum PluralCategory: String, CaseIterable {
    case zero, one, two, few, many, other

    static func category(for n: Int, language: String) -> PluralCategory {
        let lang = LanguageTag(language).language
        let n = abs(n)
        let mod10 = n % 10, mod100 = n % 100
        switch lang {
        case "ru", "uk", "be":
            if mod10 == 1 && mod100 != 11 { return .one }
            if (2...4).contains(mod10) && !(12...14).contains(mod100) { return .few }
            return .many
        case "ar":
            if n == 0 { return .zero }
            if n == 1 { return .one }
            if n == 2 { return .two }
            if (3...10).contains(mod100) { return .few }
            if (11...99).contains(mod100) { return .many }
            return .other
        case "ja", "zh", "ko":
            return .other
        default:
            return n == 1 ? .one : .other
        }
    }
}

/// Minimal BCP 47 parsing: language, optional script, optional region.
struct LanguageTag: Equatable {
    var language: String
    var script: String?
    var region: String?

    init(_ tag: String) {
        let parts = tag.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        language = (parts.first ?? "en").lowercased()
        script = nil
        region = nil
        for part in parts.dropFirst() {
            if part.count == 4, part.allSatisfy(\.isLetter) {
                script = part.prefix(1).uppercased() + part.dropFirst().lowercased()
            } else if (part.count == 2 && part.allSatisfy(\.isLetter)) || (part.count == 3 && part.allSatisfy(\.isNumber)) {
                region = part.uppercased()
            }
        }
    }

    /// Script that is implied when the tag does not carry one explicitly.
    var effectiveScript: String? {
        if let script { return script }
        switch language {
        case "zh": return ["TW", "HK", "MO"].contains(region ?? "") ? "Hant" : "Hans"
        case "ru", "uk", "be", "bg", "sr": return language == "sr" ? nil : "Cyrl"
        case "ar", "fa", "ur": return "Arab"
        case "he": return "Hebr"
        case "ja": return "Jpan"
        case "ko": return "Kore"
        default: return "Latn"
        }
    }
}

/// Reads `Localizable.xcstrings` (JSON) and resolves strings for an explicit
/// language, never touching the global `AppleLanguages` setting.
final class StringCatalog {
    enum Entry: Equatable {
        case simple(String)
        case plural([PluralCategory: String])
    }

    static let shared = StringCatalog()

    let sourceLanguage: String
    private(set) var entries: [String: [String: Entry]] = [:]

    init(data: Data? = StringCatalog.loadDefaultData()) {
        var source = "en"
        if let data,
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            source = root["sourceLanguage"] as? String ?? "en"
            let strings = root["strings"] as? [String: Any] ?? [:]
            for (key, raw) in strings {
                guard let item = raw as? [String: Any],
                      let locs = item["localizations"] as? [String: Any] else { continue }
                var perLang: [String: Entry] = [:]
                for (lang, locRaw) in locs {
                    guard let loc = locRaw as? [String: Any] else { continue }
                    if let unit = loc["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
                        perLang[lang] = .simple(value)
                    } else if let variations = loc["variations"] as? [String: Any],
                              let plural = variations["plural"] as? [String: Any] {
                        var forms: [PluralCategory: String] = [:]
                        for (cat, formRaw) in plural {
                            guard let category = PluralCategory(rawValue: cat),
                                  let form = formRaw as? [String: Any],
                                  let unit = form["stringUnit"] as? [String: Any],
                                  let value = unit["value"] as? String else { continue }
                            forms[category] = value
                        }
                        if !forms.isEmpty { perLang[lang] = .plural(forms) }
                    }
                }
                entries[key] = perLang
            }
        }
        sourceLanguage = source
    }

    static func loadDefaultData() -> Data? {
        if let url = Bundle.main.url(forResource: "Localizable", withExtension: "xcstrings"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        // Development / test fallback: the catalog next to the sources.
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        return try? Data(contentsOf: sourceURL)
    }

    /// Languages present in the catalog for every key (complete translations).
    var completeLanguages: [String] {
        guard !entries.isEmpty else { return [sourceLanguage] }
        var counts: [String: Int] = [:]
        for perLang in entries.values {
            for lang in perLang.keys { counts[lang, default: 0] += 1 }
        }
        return counts.filter { $0.value == entries.count }.map(\.key).sorted()
    }

    /// Fallback chain: selected → same language & script → source (en) → key.
    func entry(_ key: String, language: String) -> (Entry, String)? {
        guard let perLang = entries[key] else { return nil }
        for candidate in fallbackChain(for: language) {
            if let e = perLang[candidate] { return (e, candidate) }
        }
        return nil
    }

    func fallbackChain(for language: String) -> [String] {
        let tag = LanguageTag(language)
        var chain = [language]
        let langs = Set(entries.values.flatMap(\.keys))
        for candidate in langs.sorted() where candidate != language {
            let c = LanguageTag(candidate)
            if c.language == tag.language && c.effectiveScript == tag.effectiveScript {
                chain.append(candidate)
            }
        }
        if !chain.contains(sourceLanguage) { chain.append(sourceLanguage) }
        return chain
    }

    func string(_ key: String, language: String) -> String {
        guard let (entry, _) = entry(key, language: language) else { return key }
        switch entry {
        case .simple(let s): return s
        case .plural(let forms): return forms[.other] ?? forms.values.first ?? key
        }
    }

    func plural(_ key: String, count: Int, language: String, locale: Locale) -> String {
        guard let (entry, lang) = entry(key, language: language) else { return "\(count) \(key)" }
        let template: String
        switch entry {
        case .simple(let s): template = s
        case .plural(let forms):
            let cat = PluralCategory.category(for: count, language: lang)
            template = forms[cat] ?? forms[.other] ?? forms.values.first ?? key
        }
        return String(format: template, locale: locale, count)
    }
}
