import Foundation

/// sRGB colour with components in 0...1.
struct RGB: Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
    }

    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let v = UInt32(s, radix: 16) ?? 0
        self.init(r: Double((v >> 16) & 0xFF) / 255,
                  g: Double((v >> 8) & 0xFF) / 255,
                  b: Double(v & 0xFF) / 255)
    }

    static let white = RGB(r: 1, g: 1, b: 1)
    static let black = RGB(r: 0, g: 0, b: 0)

    var hexString: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = a.luminance, lb = b.luminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func mixed(with other: RGB, amount t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    // MARK: HSL

    var hsl: (h: Double, s: Double, l: Double) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        guard mx != mn else { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        switch mx {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h /= 6
        return (h, s, l)
    }

    init(h: Double, s: Double, l: Double) {
        guard s > 0 else { self.init(r: l, g: l, b: l); return }
        func hue(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        self.init(r: hue(p, q, h + 1 / 3), g: hue(p, q, h), b: hue(p, q, h - 1 / 3))
    }
}

enum ThemeID: String, CaseIterable, Identifiable {
    case obsidian, pearl, adaptive
    var id: String { rawValue }
    static let `default` = ThemeID.obsidian
}

/// Shared design tokens of one theme.
struct ThemeTokens: Equatable {
    /// surface.base — tint of the base glass surface and of settings previews.
    var base: RGB
    /// surface.panel — nested panels and the fill in opaque mode.
    var panel: RGB
    /// stroke.decorative — thin edge highlight. Never used as the only boundary.
    var stroke: RGB
    var textPrimary: RGB
    var textSecondary: RGB
    var isDark: Bool

    /// Focus ring / meaningful boundary colour; must reach 3:1 on `panel`.
    var focus: RGB { textPrimary }
    /// Control boundary that has to be visible (3:1) on the panel.
    var controlBorder: RGB { textSecondary }
    /// Island body: Obsidian is near-black like the camera housing; the
    /// other themes use their base surface.
    var islandBody: RGB { self == .obsidian ? RGB(hex: "#0B0B0C") : base }
    var islandPrimary: RGB { textPrimary }
    var islandSecondary: RGB { textSecondary }
    /// Inner cards on the island body.
    var card: RGB { self == .obsidian ? RGB(hex: "#1C1C1E") : panel }
    /// Opacity of the theme tint over the blur, raised until text passes.
    var glassOpacity: Double { Contrast.glassOpacity(for: self) }

    static let obsidian = ThemeTokens(
        base: RGB(hex: "#202122"), panel: RGB(hex: "#414244"), stroke: RGB(hex: "#707173"),
        textPrimary: RGB(hex: "#F6F6F5"), textSecondary: RGB(hex: "#CBCBCD"), isDark: true)

    static let pearl = ThemeTokens(
        base: RGB(hex: "#D7D3CB"), panel: RGB(hex: "#F0EEE8"), stroke: RGB(hex: "#FFFFFF"),
        textPrimary: RGB(hex: "#252522"), textSecondary: RGB(hex: "#575650"), isDark: false)

    /// Muted grey-green start / fallback palette of Adaptive.
    static let adaptiveFallback = ThemeTokens(
        base: RGB(hex: "#384B4B"), panel: RGB(hex: "#637576"), stroke: RGB(hex: "#91A2A0"),
        textPrimary: RGB(hex: "#FFFFFF"), textSecondary: RGB(hex: "#FFFFFF"), isDark: true)

    static func tokens(for id: ThemeID) -> ThemeTokens {
        switch id {
        case .obsidian: return .obsidian
        case .pearl: return .pearl
        case .adaptive: return .adaptiveFallback
        }
    }

    /// Builds an Adaptive palette from a seed colour (artwork or wallpaper),
    /// keeping the muted character and guaranteeing text contrast on the panel.
    static func adaptive(seed: RGB) -> ThemeTokens {
        let (h, s, _) = seed.hsl
        let sat = min(max(s * 0.45, 0.06), 0.28)
        let base = RGB(h: h, s: sat, l: 0.25)
        var panel = RGB(h: h, s: sat, l: 0.42)
        let stroke = RGB(h: h, s: sat * 0.8, l: 0.62)
        let secondary = RGB(hex: "#E8EFEE")
        panel = Contrast.adjustFill(panel, forText: secondary, minimum: Contrast.textMinimum)
        panel = Contrast.adjustFill(panel, forText: .white, minimum: Contrast.textMinimum)
        return ThemeTokens(base: base, panel: panel, stroke: stroke,
                           textPrimary: .white, textSecondary: secondary, isDark: true)
    }
}

enum Contrast {
    static let textMinimum = 4.5
    static let nonTextMinimum = 3.0

    /// Moves a fill away from the text colour until the pair reaches `minimum`.
    static func adjustFill(_ fill: RGB, forText text: RGB, minimum: Double) -> RGB {
        var f = fill
        let target: RGB = text.luminance > 0.5 ? .black : .white
        var step = 0
        while RGB.contrast(f, text) < minimum && step < 60 {
            f = f.mixed(with: target, amount: 0.04)
            step += 1
        }
        return f
    }

    /// Lowest tint opacity (≥ 0.86 for the glass look) at which both text
    /// colours stay ≥ 4.5:1 on the base tint over a black or white backdrop.
    static func glassOpacity(for t: ThemeTokens) -> Double {
        var alpha = 0.86
        while alpha < 1 {
            let ok = [RGB.black, RGB.white].allSatisfy { backdrop in
                let surface = backdrop.mixed(with: t.base, amount: alpha)
                return RGB.contrast(t.textPrimary, surface) >= textMinimum
                    && RGB.contrast(t.textSecondary, surface) >= textMinimum
            }
            if ok { return alpha }
            alpha += 0.01
        }
        return 1
    }

    /// Returns failures (descriptions) of a token set against the thresholds.
    static func audit(_ t: ThemeTokens) -> [String] {
        var failures: [String] = []
        if RGB.contrast(t.textPrimary, t.panel) < textMinimum { failures.append("primary/panel") }
        if RGB.contrast(t.textSecondary, t.panel) < textMinimum { failures.append("secondary/panel") }
        if RGB.contrast(t.focus, t.panel) < nonTextMinimum { failures.append("focus/panel") }
        if RGB.contrast(t.controlBorder, t.panel) < nonTextMinimum { failures.append("control/panel") }
        return failures
    }
}
