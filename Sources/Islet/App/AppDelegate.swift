import AppKit
import Carbon.HIToolbox
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?
    private var model: AppModel!
    private var coordinator: IslandWindowCoordinator!
    private var settings: SettingsWindowController!
    private let splash = SplashController()
    private var statusItem: NSStatusItem!
    private var hotKeys: [GlobalHotKey] = []
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // Snapshot tooling must never touch the user's real preferences.
        let isSnapshot = ProcessInfo.processInfo.environment["ISLET_SNAPSHOT"] != nil
        let model = AppModel(defaults: isSnapshot ? (UserDefaults(suiteName: "islet.snapshot") ?? .standard) : .standard)
        self.model = model
        model.language.startObservingSystem()
        if DebugTools.runIfRequested(model: model) { return }
        settings = SettingsWindowController(model: model)
        coordinator = IslandWindowCoordinator(model: model)
        coordinator.onVisibilityChange = { [weak self] in self?.rebuildMenu() }

        setupStatusItem()
        model.language.$resolved.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.rebuildMenu()
                self?.settings.retitle()
            }
        }.store(in: &bag)
        model.interaction.$state.sink { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildMenu() }
        }.store(in: &bag)

        // Carbon hot keys need no permission.
        // ⌃⌥Space: keyboard entry into the island. ⌥Space: command bar.
        if let k = GlobalHotKey(id: 1, keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), action: { [weak self] in
            self?.model.interaction.toggleFromMenu()
        }) { hotKeys.append(k) }
        if let k = GlobalHotKey(id: 2, keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), action: { [weak self] in
            self?.openCommandBar()
        }) { hotKeys.append(k) }

        if model.showSplash {
            splash.show(model: model) { [weak self] in self?.coordinator.start() }
        } else {
            coordinator.start()
        }
    }

    // MARK: Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: AppInfo.name)
            image?.isTemplate = true
            button.image = image
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let model else { return }
        let l = model.language
        let menu = NSMenu()
        if model.islandHidden {
            let hidden = NSMenuItem(title: l.t("menu.hidden"), action: nil, keyEquivalent: "")
            hidden.isEnabled = false
            menu.addItem(hidden)
            menu.addItem(.separator())
        }
        let expanded = model.interaction.state == .expanded
        let toggle = NSMenuItem(title: l.t(expanded ? "menu.collapse" : "menu.expand"),
                                action: #selector(toggleIsland), keyEquivalent: " ")
        toggle.keyEquivalentModifierMask = [.control, .option]
        toggle.target = self
        toggle.isEnabled = !model.islandHidden
        menu.addItem(toggle)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: l.t("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let about = NSMenuItem(title: l.t("menu.about"), action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: l.t("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.setAccessibilityLabel(AppInfo.name)
        statusItem.button?.toolTip = AppInfo.name
    }

    @objc private func toggleIsland() { model.interaction.toggleFromMenu() }
    @objc func openSettings() {
        model.interaction.collapse()
        settings.show()
    }
    @objc private func openAbout() { settings.show() }

    func openCommandBar() {
        if model.interaction.state == .expanded && model.selectedModule == .command {
            model.interaction.collapse()
            return
        }
        model.commandQuery = ""
        model.selectedModule = .command
        model.interaction.expand(keyboard: true)
    }
}

/// Minimal Carbon global hot key wrapper (works without Accessibility).
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32
    private let action: @MainActor () -> Void

    init?(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.id = id
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            guard hk.id == me.id else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { MainActor.assumeIsolated { me.action() } }
            return noErr
        }, 1, &spec, ptr, &handler)
        guard status == noErr else { return nil }
        let hkID = EventHotKeyID(signature: OSType(0x49534C54), id: id) // 'ISLT'
        guard RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref) == noErr else {
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
