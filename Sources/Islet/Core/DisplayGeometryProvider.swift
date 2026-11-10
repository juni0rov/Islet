import AppKit

/// Reads a fresh `NSScreen.screens` snapshot on the main actor.
@MainActor
enum DisplayGeometryProvider {
    static func snapshots() -> [ScreenSnapshot] {
        NSScreen.screens.map(snapshot(of:))
    }

    static func snapshot(of screen: NSScreen) -> ScreenSnapshot {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        var snap = ScreenSnapshot(
            displayID: number?.uint32Value,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            backingScale: screen.backingScaleFactor,
            safeAreaTop: nil,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil,
            name: screen.localizedName
        )
        if #available(macOS 12.0, *) {
            snap.safeAreaTop = screen.safeAreaInsets.top
            snap.auxiliaryTopLeft = screen.auxiliaryTopLeftArea
            snap.auxiliaryTopRight = screen.auxiliaryTopRightArea
        }
        return snap
    }

    static func screen(withID id: UInt32?) -> NSScreen? {
        guard let id else { return nil }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    /// Preferred screen: explicit choice if connected, else a confirmed notch,
    /// else the primary screen. Mirrored displays share one logical area.
    nonisolated static func chooseScreen(from snaps: [ScreenSnapshot], preferredID: UInt32?) -> ScreenSnapshot? {
        if let preferredID, let s = snaps.first(where: { $0.displayID == preferredID }) { return s }
        if let notched = snaps.first(where: {
            if case .confirmed = IslandPlacementEngine.classify($0) { return true }
            return false
        }) { return notched }
        return snaps.first
    }
}
