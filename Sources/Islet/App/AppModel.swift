import AppKit
import Combine
import SwiftUI

enum AppInfo {
    static let name = "Islet"
    static let author = "juni0rov"
    static let repoURL = URL(string: "https://github.com/juni0rov/Islet")!
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}

/// System accessibility display options, kept live.
@MainActor
final class AccessibilityState: ObservableObject {
    @Published private(set) var reduceTransparency = false
    @Published private(set) var increaseContrast = false
    @Published private(set) var reduceMotion = false
    private var observer: NSObjectProtocol?

    init() {
        read()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.read() } }
    }

    private func read() {
        let ws = NSWorkspace.shared
        reduceTransparency = ws.accessibilityDisplayShouldReduceTransparency
            || ProcessInfo.processInfo.environment["ISLET_OPAQUE"] == "1"
        increaseContrast = ws.accessibilityDisplayShouldIncreaseContrast
        reduceMotion = ws.accessibilityDisplayShouldReduceMotion
    }

    /// The island's signature motion: a soft spring, or a short fade.
    func spring(_ response: Double = 0.42, damping: Double = 0.8) -> Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: response, dampingFraction: damping)
    }
}

/// Root of app state. Module state lives here, separate from any window.
@MainActor
final class AppModel: ObservableObject {
    static let previewEnabledKey = "islet.preview.enabled"
    static let previewDelayKey = "islet.preview.delay"
    static let splashKey = "islet.splash"
    static let displayKey = "islet.display"
    static let mascotKey = "islet.mascot"
    static let toastsKey = "islet.toasts"
    static let timeKey = "islet.wing.time"
    static let mascotKindKey = "islet.mascot.kind"
    static let temperatureKey = "islet.wing.temperature"

    let defaults: UserDefaults
    let language: LanguageStore
    let theme: ThemeStore
    let accessibility = AccessibilityState()
    let interaction = IslandInteraction()
    let media = MediaController()
    let timer = TimerModel()
    let battery = BatteryMonitor()
    let shelf = ShelfModel()
    let clipboard = ClipboardHistory()
    let weather = WeatherService()
    let activity = ActivityCenter()
    let cursor = CursorTracker()
    let dock = AppDock()
    let notes = NotesModel()

    @Published var selectedModule: IslandModule = .home
    @Published var placementMode: IslandMode = .floating
    /// Camera housing size in points (notch mode only).
    @Published var notchSize: CGSize = .zero
    @Published var islandHidden = false
    @Published var classification: NotchClassification = .unknown
    @Published var dropTargeted = false
    @Published var commandQuery = ""

    @Published var previewEnabled: Bool {
        didSet { defaults.set(previewEnabled, forKey: Self.previewEnabledKey); interaction.previewEnabled = previewEnabled }
    }
    /// Hover delay in seconds.
    @Published var previewDelay: Double {
        didSet { defaults.set(previewDelay, forKey: Self.previewDelayKey); interaction.previewDelay = previewDelay }
    }
    @Published var showSplash: Bool {
        didSet { defaults.set(showSplash, forKey: Self.splashKey) }
    }
    @Published var showMascot: Bool {
        didSet { defaults.set(showMascot, forKey: Self.mascotKey) }
    }
    /// Which character lives next to the notch.
    @Published var mascot: MascotKind {
        didSet { defaults.set(mascot.rawValue, forKey: Self.mascotKindKey) }
    }
    /// Wing contents, each optional.
    @Published var showTime: Bool {
        didSet { defaults.set(showTime, forKey: Self.timeKey) }
    }
    @Published var showTemperature: Bool {
        didSet { defaults.set(showTemperature, forKey: Self.temperatureKey) }
    }
    /// Height of the menu bar on the island's screen (0 when hidden).
    @Published var menuBarHeight: CGFloat = 0
    @Published var showToasts: Bool {
        didSet { defaults.set(showToasts, forKey: Self.toastsKey) }
    }
    /// 0 = automatic, else a CGDirectDisplayID.
    @Published var preferredDisplayID: UInt32 {
        didSet { defaults.set(Int(preferredDisplayID), forKey: Self.displayKey) }
    }

    private var bag = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Self.previewEnabledKey: true,
            Self.previewDelayKey: 0.2,
            Self.splashKey: true,
            Self.displayKey: 0,
            Self.mascotKey: true,
            Self.toastsKey: true,
            Self.timeKey: true,
            Self.temperatureKey: true
        ])
        language = LanguageStore(defaults: defaults)
        theme = ThemeStore(defaults: defaults)
        previewEnabled = defaults.bool(forKey: Self.previewEnabledKey)
        previewDelay = defaults.double(forKey: Self.previewDelayKey)
        showSplash = defaults.bool(forKey: Self.splashKey)
        showMascot = defaults.bool(forKey: Self.mascotKey)
        showToasts = defaults.bool(forKey: Self.toastsKey)
        showTime = defaults.bool(forKey: Self.timeKey)
        mascot = MascotKind(rawValue: defaults.string(forKey: Self.mascotKindKey) ?? "") ?? .cat
        showTemperature = defaults.bool(forKey: Self.temperatureKey)
        preferredDisplayID = UInt32(clamping: defaults.integer(forKey: Self.displayKey))
        interaction.previewEnabled = previewEnabled
        interaction.previewDelay = previewDelay
        wireActivities()
    }

    // MARK: Toasts

    private func wireActivities() {
        clipboard.onCopy = { [weak self] item in
            guard let self else { return }
            self.toast(IslandActivity(symbol: item.isLink ? "link" : "doc.on.clipboard",
                                      title: self.language.t("toast.copied"),
                                      subtitle: item.text.replacingOccurrences(of: "\n", with: " ")))
        }
        shelf.onAdd = { [weak self] url in
            guard let self else { return }
            self.toast(IslandActivity(symbol: "tray.and.arrow.down.fill",
                                      title: self.language.t("toast.shelf"),
                                      subtitle: isolated(url.lastPathComponent),
                                      image: NSWorkspace.shared.icon(forFile: url.path)))
        }
        timer.onFinish = { [weak self] in
            guard let self else { return }
            self.toast(IslandActivity(symbol: "timer", title: self.language.t("timer.done"),
                                      subtitle: TimerModel.format(self.timer.total), tint: .orange), force: true)
        }
        media.onTrackChange = { [weak self] track, image in
            guard let self else { return }
            if let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                self.theme.setCover(id: "\(track.player.rawValue)|\(track.title)|\(track.artist)", image: cg)
            } else {
                self.theme.setCover(id: "", image: nil)
            }
            guard track.playing else { return }
            self.toast(IslandActivity(symbol: "music.note", title: isolated(track.title),
                                      subtitle: isolated(track.artist), image: image))
        }
        // Keep the Adaptive theme off a stale cover once playback stops.
        media.$track.map { $0 == nil }.removeDuplicates().sink { [weak self] stopped in
            if stopped { self?.theme.setCover(id: "", image: nil) }
        }.store(in: &bag)
    }

    func toast(_ activity: IslandActivity, force: Bool = false) {
        guard showToasts || force else { return }
        // Never cover the open panel; the panel shows the same state anyway.
        guard interaction.state == .compact else { return }
        self.activity.show(activity)
    }

    // MARK: Sizes

    /// Flared top corners of the notch shape (they sit outside the body).
    static let earRadius: CGFloat = 10
    /// The island overlaps the camera housing by this much on each side so
    /// no sliver of the hardware edge peeks out.
    static let notchOverscan: CGFloat = 2

    /// What the idle wings show, given the toggles and available data.
    var idleTemperature: String? { showTemperature ? weather.temperatureText : nil }
    /// Temperature goes left (with its icon) when there is no cat there.
    var temperatureOnLeft: Bool { !showMascot && idleTemperature != nil }

    /// Width of each side "wing" next to the camera housing. Both wings are
    /// equally wide so the island stays centred on the camera; with nothing
    /// to show the island is exactly as wide as the housing.
    var wingWidth: CGFloat {
        switch summary {
        case .timer: return 78
        case .media: return 46
        case .idle:
            let left: CGFloat = showMascot ? 44 : (temperatureOnLeft ? 66 : 0)
            let tempRight = showMascot && idleTemperature != nil
            let right: CGFloat = showTime ? (tempRight ? 104 : 74) : (tempRight ? 52 : 0)
            return max(left, right)
        }
    }

    /// Height of the top band: exactly the camera housing in notch mode, so
    /// the island adapts to whatever notch this Mac has.
    var bandHeight: CGFloat {
        placementMode == .notch ? max(notchSize.height + Self.notchOverscan, 24) : 34
    }

    var compactSize: CGSize {
        if placementMode == .notch {
            return CGSize(width: notchSize.width + 2 * (wingWidth + Self.notchOverscan + Self.earRadius), height: bandHeight)
        }
        return CGSize(width: 250, height: 36)
    }

    var activitySize: CGSize {
        CGSize(width: max(compactSize.width + 120, 430), height: bandHeight + 56)
    }

    var expandedSize: CGSize {
        CGSize(width: 700, height: bandHeight + 250)
    }

    /// The largest the island ever gets; the panel is this big (plus shadow).
    var panelSize: CGSize {
        CGSize(width: expandedSize.width + 2 * Self.shadowMargin, height: expandedSize.height + Self.shadowMargin)
    }

    static let shadowMargin: CGFloat = 28

    func islandSize(state: IslandState, activity: IslandActivity?) -> CGSize {
        switch state {
        case .expanded, .preview: return expandedSize
        case .compact: return activity != nil ? activitySize : compactSize
        }
    }

    /// Kept for snapshot tooling and settings previews.
    func desiredSize(for state: IslandState) -> CGSize {
        islandSize(state: state, activity: nil)
    }

    /// What the compact wings summarise.
    enum Summary { case timer, media, idle }
    var summary: Summary {
        if timer.running || timer.finished { return .timer }
        if media.track?.playing == true { return .media }
        return .idle
    }
}
