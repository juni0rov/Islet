import AppKit
import SwiftUI

/// Developer aids, inactive unless an environment variable is set:
///   ISLET_GEOMETRY=1        print screen snapshots and computed placements
///   ISLET_SNAPSHOT=<dir>    render splash / island states / settings to PNGs and quit
@MainActor
enum DebugTools {
    static func runIfRequested(model: AppModel) -> Bool {
        let env = ProcessInfo.processInfo.environment
        if env["ISLET_GEOMETRY"] == "1" { printGeometry(model: model) }
        guard let dir = env["ISLET_SNAPSHOT"] else { return false }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let mode = env["ISLET_SNAPSHOT_MODE"], mode == "notch" {
            model.placementMode = .notch
            model.notchSize = CGSize(width: 179, height: 32)
            model.menuBarHeight = 37
            if env["ISLET_SNAPSHOT_WINGS"] == "none" { model.showMascot = false; model.showTime = false; model.showTemperature = false }
            if env["ISLET_SNAPSHOT_WINGS"] == "time" { model.showMascot = false; model.showTemperature = false }
        }
        if let lang = env["ISLET_SNAPSHOT_LANG"] { model.language.select(lang) }
        if let t = env["ISLET_SNAPSHOT_THEME"], let id = ThemeID(rawValue: t) { model.theme.select(id) }
        model.timer.setMinutes(25)
        model.shelf.add([URL(fileURLWithPath: "/Applications/Safari.app"),
                         URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")])
        model.media.apply(state: "Playing", title: "Midnight City", artist: "M83", album: "Hurry Up", duration: 243, player: .spotify)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            model.activity.dismiss()
            model.activity.dismiss()
            render(SplashView(), model: model, size: CGSize(width: 340, height: 260), to: url.appendingPathComponent("splash.png"))
            let panel = model.panelSize
            model.interaction.debugForce(.compact)
            model.activity.dismiss()
            render(IslandRootView(), model: model, size: panel, to: url.appendingPathComponent("island-compact.png"))
            model.media.apply(state: "Stopped", title: "", artist: "", album: "", duration: 0, player: .spotify)
            render(IslandRootView(), model: model, size: panel, to: url.appendingPathComponent("island-compact-idle.png"))
            model.activity.show(IslandActivity(symbol: "doc.on.clipboard", title: model.language.t("toast.copied"),
                                               subtitle: "https://github.com/juni0rov/Islet"), duration: 60)
            render(IslandRootView(), model: model, size: panel, to: url.appendingPathComponent("island-toast.png"))
            model.activity.dismiss()
            model.media.apply(state: "Playing", title: "Midnight City", artist: "M83", album: "Hurry Up", duration: 243, player: .spotify)
            model.interaction.debugForce(.expanded)
            for module in IslandModule.allCases {
                model.selectedModule = module
                if module == .command { model.commandQuery = "200+15%" }
                render(IslandRootView(), model: model, size: panel,
                       to: url.appendingPathComponent("island-expanded-\(module.rawValue).png"))
            }
            render(SettingsView().environmentObject(model), model: model, size: CGSize(width: 720, height: 520),
                   to: url.appendingPathComponent("settings.png"))
            render(SettingsView(startTab: .behavior).environmentObject(model), model: model, size: CGSize(width: 720, height: 640),
                   to: url.appendingPathComponent("settings-behavior.png"))
            render(SettingsView(startTab: .behavior, sidebar: false).environmentObject(model), model: model,
                   size: CGSize(width: 720, height: 300), to: url.appendingPathComponent("settings-nosidebar.png"))
            render(HStack(spacing: 14) {
                ForEach(MascotKind.allCases) { k in MascotView(size: 44, kind: k, interactive: false) }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.black)),
                   model: model, size: CGSize(width: 560, height: 100), to: url.appendingPathComponent("mascots.png"))
            print("snapshots written to \(url.path)")
            NSApp.terminate(nil)
        }
        return true
    }

    private static func render<V: View>(_ view: V, model: AppModel, size: CGSize, to file: URL) {
        let root = ZStack {
            LinearGradient(colors: [Color(red: 0.45, green: 0.52, blue: 0.56), Color(red: 0.15, green: 0.18, blue: 0.2)],
                           startPoint: .top, endPoint: .bottom)
            view
        }
        .frame(width: size.width, height: size.height)
        .environmentObject(model)
        .environmentObject(model.language)
        .environmentObject(model.theme)
        .environmentObject(model.accessibility)
        .environmentObject(model.interaction)
        .environmentObject(model.timer)
        .environmentObject(model.media)
        .environmentObject(model.battery)
        .environmentObject(model.shelf)
        .environmentObject(model.clipboard)
        .environmentObject(model.weather)
        .environmentObject(model.activity)
        .environmentObject(model.cursor)
        .environmentObject(model.dock)
        .environmentObject(model.notes)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
        window.orderOut(nil)
    }

    static func printGeometry(model: AppModel) {
        for s in DisplayGeometryProvider.snapshots() {
            print("screen \(s.displayID ?? 0) \(s.name) frame=\(s.frame) visible=\(s.visibleFrame) scale=\(s.backingScale)")
            print("  safeTop=\(s.safeAreaTop.map { "\($0)" } ?? "nil") auxL=\(String(describing: s.auxiliaryTopLeft)) auxR=\(String(describing: s.auxiliaryTopRight))")
            print("  class=\(IslandPlacementEngine.classify(s))")
            for st in [IslandState.compact, .expanded] {
                let p = IslandPlacementEngine.place(s, size: st == .compact ? CGSize(width: 371, height: 32) : model.panelSize, menuBarThickness: NSStatusBar.system.thickness)
                print("  \(st): \(p.map { "\($0.mode) frame=\($0.frame) anchorX=\($0.anchorX)" } ?? "hidden")")
            }
        }
    }
}

