import AppKit
import IOKit.ps
import SwiftUI
import UniformTypeIdentifiers

/// Tabs of the expanded island.
enum IslandModule: String, CaseIterable, Identifiable {
    case home, clipboard, shelf, notes, weather, command
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .clipboard: return "doc.on.clipboard"
        case .shelf: return "tray"
        case .notes: return "square.and.pencil"
        case .weather: return "cloud.sun"
        case .command: return "magnifyingglass"
        }
    }

    var titleKey: String { "module.\(rawValue)" }
}

// MARK: Timer

@MainActor
final class TimerModel: ObservableObject {
    @Published private(set) var total: TimeInterval = 5 * 60
    @Published private(set) var remaining: TimeInterval = 5 * 60
    @Published private(set) var running = false
    @Published private(set) var finished = false
    var onFinish: (() -> Void)?

    private var ticker: Timer?
    private var endDate: Date?

    var progress: Double { total > 0 ? 1 - remaining / total : 0 }
    var isActive: Bool { running || (remaining < total && remaining > 0) }

    func setMinutes(_ minutes: Int) {
        stopTicker()
        total = TimeInterval(max(1, minutes) * 60)
        remaining = total
        running = false
        finished = false
    }

    func start() {
        guard remaining > 0 else { return }
        finished = false
        endDate = Date().addingTimeInterval(remaining)
        running = true
        // Ticks only while running; idle keeps no timers alive.
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func pause() {
        tick()
        running = false
        stopTicker()
    }

    func reset() {
        stopTicker()
        running = false
        finished = false
        remaining = total
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            stopTicker()
            running = false
            finished = true
            NSSound(named: "Glass")?.play()
            onFinish?()
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: Battery

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var percent: Int?
    @Published private(set) var charging = false
    @Published private(set) var pluggedIn = false
    private var source: CFRunLoopSource?

    init() {
        update()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { monitor.update() } }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            source = src
        }
    }

    var symbol: String {
        guard let percent else { return "powerplug" }
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    func update() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { percent = nil; return }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            percent = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : nil
            charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            pluggedIn = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return
        }
        percent = nil
    }
}

// MARK: Shelf

/// Temporary file shelf: drop files on the island, drag them out later.
@MainActor
final class ShelfModel: ObservableObject {
    @Published private(set) var items: [URL] = []
    var onAdd: ((URL) -> Void)?

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(url) {
            items.append(url)
            onAdd?(url)
        }
    }

    func remove(_ url: URL) { items.removeAll { $0 == url } }
    func clear() { items.removeAll() }

    /// Loads file URLs from drop providers.
    func accept(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url else { return }
                Task { @MainActor in self?.add([url]) }
            }
        }
        return true
    }
}

// MARK: Activity (toasts that grow out of the island)

struct IslandActivity: Equatable, Identifiable {
    let id = UUID()
    var symbol: String
    var title: String
    var subtitle: String
    var tint: Color = .white
    var image: NSImage?

    static func == (a: IslandActivity, b: IslandActivity) -> Bool { a.id == b.id }
}

@MainActor
final class ActivityCenter: ObservableObject {
    @Published private(set) var current: IslandActivity?
    private var hideWork: DispatchWorkItem?

    func show(_ activity: IslandActivity, duration: TimeInterval = 2.6) {
        current = activity
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.current = nil }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func dismiss() {
        hideWork?.cancel()
        current = nil
    }
}

// MARK: Cursor (for the mascot's eyes)

/// Pointer position, published separately so only the mascot re-renders.
@MainActor
final class CursorTracker: ObservableObject {
    @Published var location: CGPoint = .zero
    @Published var lastMove = Date()
    /// Where the mascot sits on screen, so its eyes can aim at the cursor.
    var anchor: CGPoint = .zero
}

// MARK: App dock

@MainActor
final class AppDock: ObservableObject {
    static let key = "islet.dock"
    static let defaultApps = ["com.apple.finder", "com.apple.Safari", "com.apple.Music",
                              "com.apple.Notes", "com.apple.Terminal", "com.apple.systempreferences"]
    @Published private(set) var bundleIDs: [String]

    init() {
        bundleIDs = UserDefaults.standard.stringArray(forKey: Self.key) ?? Self.defaultApps
    }

    var apps: [(id: String, url: URL)] {
        bundleIDs.compactMap { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { (id, $0) }
        }
    }

    func launch(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func add(_ url: URL) {
        guard let id = Bundle(url: url)?.bundleIdentifier, !bundleIDs.contains(id) else { return }
        bundleIDs.append(id)
        UserDefaults.standard.set(bundleIDs, forKey: Self.key)
    }

    func remove(_ id: String) {
        bundleIDs.removeAll { $0 == id }
        UserDefaults.standard.set(bundleIDs, forKey: Self.key)
    }
}

// MARK: Notes

@MainActor
final class NotesModel: ObservableObject {
    static let key = "islet.notes"
    @Published var text: String {
        didSet { UserDefaults.standard.set(text, forKey: Self.key) }
    }

    init() {
        text = UserDefaults.standard.string(forKey: Self.key) ?? ""
    }
}
