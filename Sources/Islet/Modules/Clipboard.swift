import AppKit

/// Remembers copied text (public NSPasteboard change count; no permission).
@MainActor
final class ClipboardHistory: ObservableObject {
    struct Item: Codable, Identifiable, Equatable {
        var id = UUID()
        var text: String
        var date: Date
        var pinned: Bool = false
        var sourceApp: String?

        var isLink: Bool {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t.hasPrefix("http://") || t.hasPrefix("https://")) && !t.contains(" ")
        }
    }

    static let key = "islet.clipboard"
    static let limit = 60

    @Published private(set) var items: [Item] = []
    @Published var query = ""
    var onCopy: ((Item) -> Void)?

    private var changeCount = NSPasteboard.general.changeCount
    private var poller: Timer?
    /// Set while Islet itself writes, so we don't announce our own copies.
    private var ignoreNextChange = false

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
        }
        let t = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        poller = t
    }

    var filtered: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? items : items.filter { $0.text.lowercased().contains(q) }
        return base.filter(\.pinned) + base.filter { !$0.pinned }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != changeCount else { return }
        changeCount = pb.changeCount
        if ignoreNextChange { ignoreNextChange = false; return }
        // Respect apps that mark secrets (password managers) as transient.
        let types = pb.types ?? []
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            || types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) { return }
        guard let text = pb.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName
        if let idx = items.firstIndex(where: { $0.text == text }) {
            var item = items.remove(at: idx)
            item.date = Date()
            items.insert(item, at: 0)
        } else {
            items.insert(Item(text: text, date: Date(), sourceApp: app), at: 0)
        }
        trim()
        save()
        if let first = items.first { onCopy?(first) }
    }

    func copy(_ item: Item) {
        write(item.text)
    }

    func write(_ text: String) {
        ignoreNextChange = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        changeCount = pb.changeCount
        ignoreNextChange = false
        if let idx = items.firstIndex(where: { $0.text == text }) {
            var item = items.remove(at: idx)
            item.date = Date()
            items.insert(item, at: 0)
        } else {
            items.insert(Item(text: text, date: Date(), sourceApp: "Islet"), at: 0)
        }
        trim()
        save()
    }

    func togglePin(_ item: Item) {
        guard let i = items.firstIndex(of: item) else { return }
        items[i].pinned.toggle()
        save()
    }

    func delete(_ item: Item) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearUnpinned() {
        items.removeAll { !$0.pinned }
        save()
    }

    private func trim() {
        var unpinned = 0
        items = items.filter { item in
            if item.pinned { return true }
            unpinned += 1
            return unpinned <= Self.limit
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// Text transformations from the video: keyboard-layout fix, case, transliteration.
enum TextTools {
    private static let en = Array("`qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?@#$^&")
    private static let ru = Array("ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,\"№;:?")

    /// "ghbdtn" → "привет" and back, picking the direction by the letters found.
    static func fixLayout(_ s: String) -> String {
        let latin = s.filter { $0.isASCII && $0.isLetter }.count
        let cyr = s.filter { ru.contains($0) && $0.isLetter }.count
        let (from, to) = latin >= cyr ? (en, ru) : (ru, en)
        var map: [Character: Character] = [:]
        for (a, b) in zip(from, to) where map[a] == nil { map[a] = b }
        return String(s.map { map[$0] ?? $0 })
    }

    static func transliterate(_ s: String) -> String {
        let table: [Character: String] = [
            "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "zh", "з": "z",
            "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r",
            "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch",
            "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya"
        ]
        var out = ""
        for ch in s {
            let lower = Character(ch.lowercased())
            if let t = table[lower] {
                out += ch.isUppercase ? t.prefix(1).uppercased() + t.dropFirst() : t
            } else {
                out.append(ch)
            }
        }
        return out
    }
}

/// Small, safe arithmetic evaluator for the command bar: + − × ÷ ^ % ( ).
/// (NSExpression raises Objective-C exceptions on bad input, so it is avoided.)
enum Calculator {
    static func evaluate(_ input: String) -> Double? {
        let s = input.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty, s.contains(where: { "+-*/^%".contains($0) }),
              s.allSatisfy({ "0123456789.+-*/^%()".contains($0) }) else { return nil }
        var p = Parser(chars: Array(s))
        guard let v = p.expression(), p.i == p.chars.count, v.isFinite else { return nil }
        return v
    }

    private struct Parser {
        let chars: [Character]
        var i = 0

        mutating func peek() -> Character? { i < chars.count ? chars[i] : nil }

        mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while let c = peek(), c == "+" || c == "-" {
                i += 1
                guard var r = term() else { return nil }
                // "200 + 15%" means 200 + 15% of 200.
                if peek() == "%" { i += 1; r = v * r / 100 }
                v = c == "+" ? v + r : v - r
            }
            return v
        }

        mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while let c = peek(), c == "*" || c == "/" {
                i += 1
                guard var r = power() else { return nil }
                if peek() == "%" { i += 1; r /= 100 }
                v = c == "*" ? v * r : v / r
            }
            return v
        }

        mutating func power() -> Double? {
            guard let b = unary() else { return nil }
            if peek() == "^" {
                i += 1
                guard let e = power() else { return nil }
                return pow(b, e)
            }
            return b
        }

        mutating func unary() -> Double? {
            if peek() == "-" { i += 1; return unary().map { -$0 } }
            if peek() == "+" { i += 1; return unary() }
            return primary()
        }

        mutating func primary() -> Double? {
            if peek() == "(" {
                i += 1
                let v = expression()
                guard peek() == ")" else { return nil }
                i += 1
                return v
            }
            let start = i
            while let c = peek(), c.isNumber || c == "." { i += 1 }
            guard i > start else { return nil }
            return Double(String(chars[start..<i]))
        }
    }
}
