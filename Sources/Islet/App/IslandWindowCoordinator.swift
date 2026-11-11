import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating panel that hosts the island. It is as large as
/// the expanded island and stays put; the island shape animates inside it.
/// Mouse events pass through everywhere except over the visible island.
final class IslandPanel: NSPanel {
    var allowsKey = false
    var onEscape: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 34),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        // Above the menu bar so the island can grow out of the notch.
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }

    /// Borderless panels may sit over the menu bar; don't let AppKit push it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class IslandWindowCoordinator {
    private let model: AppModel
    private var panel: IslandPanel?
    private var currentDisplayID: UInt32?
    private var pendingRelayout: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var monitors: [Any] = []
    private var pointerInside = false

    var onVisibilityChange: (() -> Void)?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        buildPanel()
        observe()
        relayout()
    }

    private func buildPanel() {
        let panel = IslandPanel()
        let root = IslandRootView()
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
        let host = NSHostingView(rootView: AnyView(root))
        host.sizingOptions = []
        host.safeAreaRegions = []
        panel.contentView = host
        panel.onEscape = { [weak self] in self?.model.interaction.escape() }
        self.panel = panel
    }

    // MARK: Observation

    private func observe() {
        model.interaction.$state
            .removeDuplicates()
            .sink { [weak self] state in
                DispatchQueue.main.async { self?.stateChanged(state) }
            }
            .store(in: &bag)

        model.activity.$current
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateHitTesting() } }
            .store(in: &bag)

        model.$preferredDisplayID.dropFirst()
            .sink { [weak self] _ in self?.scheduleRelayout() }
            .store(in: &bag)

        // Fit sliders change the band height, and with it the panel size.
        model.$fitHeight.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.relayout() } }
            .store(in: &bag)

        let app = NotificationCenter.default
        add(app, NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.screensChanged() }
        add(app, NSApplication.didBecomeActiveNotification) { [weak self] in self?.scheduleRelayout() }

        let ws = NSWorkspace.shared.notificationCenter
        add(ws, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.model.interaction.collapse()
            self?.scheduleRelayout()
        }
        add(ws, NSWorkspace.didWakeNotification) { [weak self] in self?.scheduleRelayout() }
        add(ws, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.scheduleRelayout() }

        // Mouse-moved / dragged / click monitors. Global mouse monitors need no
        // Accessibility permission (only keyboard monitors would).
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: moveMask, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return e
        }) { monitors.append(l) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedOutside() }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] e in
            MainActor.assumeIsolated {
                if e.window === self?.panel { self?.model.interaction.clickedInside() }
            }
            return e
        }) { monitors.append(l) }
    }

    private func add(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { block() }
        }
        observers.append((center, token))
    }

    // MARK: Pointer

    /// Visible island rect in screen coordinates (top-centred in the panel).
    private func islandRect() -> NSRect? {
        guard let panel, panel.isVisible else { return nil }
        let size = model.islandSize(state: model.interaction.state, activity: model.activity.current)
        let f = panel.frame
        return NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
    }

    private func mouseMoved() {
        let p = NSEvent.mouseLocation
        model.cursor.location = p
        model.cursor.lastMove = Date()
        guard var rect = islandRect() else { return }
        if let f = panel?.frame {
            model.cursor.anchor = CGPoint(x: f.midX - model.compactSize.width / 2 + 28,
                                          y: f.maxY - model.bandHeight / 2)
        }
        // A little slack, and the very top pixel row above the notch counts.
        rect = rect.insetBy(dx: -4, dy: -4)
        let inside = rect.contains(p)
        if inside != pointerInside {
            pointerInside = inside
            if inside { model.interaction.pointerEntered() } else { model.interaction.pointerExited() }
        }
        panel?.ignoresMouseEvents = !inside
    }

    private func clickedOutside() {
        guard let rect = islandRect(), !rect.contains(NSEvent.mouseLocation) else { return }
        model.interaction.clickedOutside()
    }

    private func updateHitTesting() {
        guard let rect = islandRect() else { return }
        let inside = rect.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
        panel?.ignoresMouseEvents = !inside
    }

    private func stateChanged(_ state: IslandState) {
        guard let panel else { return }
        if state == .expanded {
            // Pinned: may take keyboard focus (search fields, notes, Esc).
            panel.allowsKey = true
            if model.interaction.keyboardFocusRequested || pointerInside { panel.makeKey() }
        } else {
            if panel.isKeyWindow { panel.resignKey() }
            panel.allowsKey = false
        }
        if state != .compact { relayout() }   // re-check geometry before opening
        updateHitTesting()
    }

    // MARK: Screens

    /// A vanished screen loses its window immediately; the rest is coalesced.
    private func screensChanged() {
        let ids = Set(DisplayGeometryProvider.snapshots().compactMap(\.displayID))
        if let current = currentDisplayID, !ids.contains(current) {
            panel?.orderOut(nil)
            model.interaction.reset()
            currentDisplayID = nil
        }
        scheduleRelayout()
    }

    func scheduleRelayout() {
        pendingRelayout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.relayout() }
        }
        pendingRelayout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    /// Recomputes geometry from a fresh snapshot and places the panel.
    func relayout() {
        guard let panel else { return }
        let snaps = DisplayGeometryProvider.snapshots()
        let preferred = model.preferredDisplayID == 0 ? nil : model.preferredDisplayID
        guard let target = DisplayGeometryProvider.chooseScreen(from: snaps, preferredID: preferred) else {
            hide(); return
        }
        let thickness = NSStatusBar.system.thickness
        // First learn the mode and notch size, then size the panel for it.
        guard let probe = IslandPlacementEngine.place(target, size: CGSize(width: 100, height: 30),
                                                      menuBarThickness: thickness) else { hide(); return }
        if model.placementMode != probe.mode { model.placementMode = probe.mode }
        let notch = probe.notch ?? .zero
        if model.notchSize != notch { model.notchSize = notch }
        let bar = target.frame.maxY - target.visibleFrame.maxY
        let menuBar: CGFloat = (bar > 0 && bar < 80) ? bar : 0
        if model.menuBarHeight != menuBar { model.menuBarHeight = menuBar }
        guard let placement = IslandPlacementEngine.place(target, size: model.panelSize,
                                                          menuBarThickness: thickness) else { hide(); return }

        if currentDisplayID != target.displayID {
            currentDisplayID = target.displayID
            model.theme.setScreen(DisplayGeometryProvider.screen(withID: target.displayID))
        }
        model.classification = IslandPlacementEngine.classify(target)
        if model.islandHidden {
            model.islandHidden = false
            onVisibilityChange?()
        }
        if panel.frame != placement.frame { panel.setFrame(placement.frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
        updateHitTesting()
    }

    private func hide() {
        panel?.orderOut(nil)
        model.interaction.reset()
        currentDisplayID = nil
        if !model.islandHidden {
            model.islandHidden = true
            onVisibilityChange?()
        }
    }
}
