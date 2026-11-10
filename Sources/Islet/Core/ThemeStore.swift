import AppKit
import ImageIO
import SwiftUI

/// Average colour of an image, computed on a tiny thumbnail.
enum DominantColor {
    static func average(of image: CGImage) -> RGB? {
        let side = 8
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        for i in 0..<(side * side) {
            let alpha = Double(px[i * 4 + 3]) / 255
            r += Double(px[i * 4]) / 255
            g += Double(px[i * 4 + 1]) / 255
            b += Double(px[i * 4 + 2]) / 255
            a += alpha
        }
        guard a > 0 else { return nil }
        return RGB(r: r / a, g: g / a, b: b / a)
    }

    static func average(ofFile url: URL) -> RGB? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { return nil }
        return average(of: thumb)
    }
}

/// Selected theme + resolved tokens. Adaptive priority:
/// media artwork → allowed wallpaper → base palette.
@MainActor
final class ThemeStore: ObservableObject {
    static let themeKey = "islet.theme"
    static let wallpaperKey = "islet.adaptive.wallpaper"

    @Published private(set) var themeID: ThemeID
    @Published var allowWallpaper: Bool {
        didSet { defaults.set(allowWallpaper, forKey: Self.wallpaperKey); recompute() }
    }
    @Published private(set) var tokens: ThemeTokens
    @Published private(set) var adaptiveSource: String = "fallback"

    /// Artwork from an already connected media source, if any.
    private var cover: (id: String, image: CGImage)?
    private var screen: NSScreen?
    private var generation = 0
    private var cache: [String: RGB] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let id = ThemeID(rawValue: defaults.string(forKey: Self.themeKey) ?? "") ?? .default
        themeID = id
        allowWallpaper = defaults.bool(forKey: Self.wallpaperKey)
        tokens = ThemeTokens.tokens(for: id)
        recompute()
    }

    func select(_ id: ThemeID) {
        themeID = id
        defaults.set(id.rawValue, forKey: Self.themeKey)
        recompute()
    }

    func setCover(id: String, image: CGImage?) {
        if let image { cover = (id, image) } else { cover = nil }
        recompute()
    }

    func setScreen(_ screen: NSScreen?) {
        self.screen = screen
        if themeID == .adaptive { recompute() }
    }

    /// Asynchronous and cached per source; stale results are dropped.
    func recompute() {
        generation += 1
        let gen = generation
        guard themeID == .adaptive else {
            tokens = ThemeTokens.tokens(for: themeID)
            adaptiveSource = "fallback"
            return
        }
        if let cover {
            let key = "cover:" + cover.id
            resolve(key: key, gen: gen) { [image = cover.image] in DominantColor.average(of: image) }
            return
        }
        if allowWallpaper, let screen,
           let url = NSWorkspace.shared.desktopImageURL(for: screen),
           url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
            resolve(key: "wall:\(url.path):\(mod)", gen: gen) { DominantColor.average(ofFile: url) }
            return
        }
        tokens = .adaptiveFallback
        adaptiveSource = "fallback"
    }

    private func resolve(key: String, gen: Int, work: @escaping @Sendable () -> RGB?) {
        if let cached = cache[key] {
            tokens = .adaptive(seed: cached)
            adaptiveSource = key
            return
        }
        Task.detached(priority: .utility) {
            let seed = work()
            await MainActor.run {
                // Theme, source or screen changed meanwhile → discard.
                guard gen == self.generation, self.themeID == .adaptive else { return }
                if let seed {
                    self.cache[key] = seed
                    self.tokens = .adaptive(seed: seed)
                    self.adaptiveSource = key
                } else {
                    self.tokens = .adaptiveFallback
                    self.adaptiveSource = "fallback"
                }
            }
        }
    }
}

extension RGB {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}
