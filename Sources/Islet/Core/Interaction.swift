import Foundation

/// Cancels a scheduled block.
struct Cancellation {
    let cancel: () -> Void
}

protocol InteractionScheduler {
    func after(_ delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellation
}

struct MainQueueScheduler: InteractionScheduler {
    func after(_ delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellation {
        let item = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return Cancellation { item.cancel() }
    }
}

enum IslandState: Int, Comparable {
    case compact, preview, expanded
    static func < (a: IslandState, b: IslandState) -> Bool { a.rawValue < b.rawValue }
}

/// Transitions between compact, hover preview and the pinned expanded panel.
final class IslandInteraction: ObservableObject {
    @Published private(set) var state: IslandState = .compact
    /// Set when the panel was opened from the keyboard and should take focus.
    @Published private(set) var keyboardFocusRequested = false

    var previewEnabled = true
    var previewDelay: TimeInterval = 0.2
    var leaveDelay: TimeInterval = 0.25

    private(set) var pointerInside = false
    private var pendingPreview: Cancellation?
    private var pendingLeave: Cancellation?
    private let scheduler: InteractionScheduler

    init(scheduler: InteractionScheduler = MainQueueScheduler()) {
        self.scheduler = scheduler
    }

    func pointerEntered() {
        pointerInside = true
        cancelLeave()
        guard state == .compact, previewEnabled else { return }
        cancelPreview()
        pendingPreview = scheduler.after(previewDelay) { [weak self] in
            guard let self, self.pointerInside, self.state == .compact else { return }
            self.pendingPreview = nil
            self.state = .preview
        }
    }

    func pointerExited() {
        pointerInside = false
        cancelPreview()
        guard state == .preview else { return }
        cancelLeave()
        pendingLeave = scheduler.after(leaveDelay) { [weak self] in
            guard let self, !self.pointerInside, self.state == .preview else { return }
            self.pendingLeave = nil
            self.state = .compact
        }
    }

    /// Click on the trigger: expands and pins, or collapses when expanded.
    func click() {
        if state == .expanded { collapse() } else { expand(keyboard: false) }
    }

    /// Any click inside the hover preview pins it open.
    func clickedInside() {
        if state == .preview { expand(keyboard: false) }
    }

    /// Clicking elsewhere on screen closes a pinned panel.
    func clickedOutside() {
        if state != .compact { collapse() }
    }

    func expand(keyboard: Bool) {
        cancelTimers()
        keyboardFocusRequested = keyboard
        state = .expanded
    }

    func toggleFromMenu() {
        if state == .expanded { collapse() } else { expand(keyboard: true) }
    }

    func escape() {
        guard state == .expanded else { return }
        collapse()
    }

    func collapse() {
        cancelTimers()
        keyboardFocusRequested = false
        state = .compact
    }

    /// Screen vanished, Space changed, etc.: drop everything in flight.
    func reset() {
        pointerInside = false
        collapse()
    }

    private func cancelPreview() { pendingPreview?.cancel(); pendingPreview = nil }
    private func cancelLeave() { pendingLeave?.cancel(); pendingLeave = nil }
    private func cancelTimers() { cancelPreview(); cancelLeave() }

    /// Snapshot tooling only.
    func debugForce(_ s: IslandState) { cancelTimers(); state = s }

    var hasPendingTimers: Bool { pendingPreview != nil || pendingLeave != nil }
}
