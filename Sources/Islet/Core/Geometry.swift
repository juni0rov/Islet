import CoreGraphics

/// Immutable snapshot of one screen, taken on the main actor from `NSScreen`.
/// Kept free of AppKit types so the placement maths stays pure and testable.
struct ScreenSnapshot: Equatable {
    var displayID: UInt32?
    var frame: CGRect
    var visibleFrame: CGRect
    var backingScale: CGFloat
    /// `safeAreaInsets.top`; `nil` when the API is unavailable.
    var safeAreaTop: CGFloat?
    var auxiliaryTopLeft: CGRect?
    var auxiliaryTopRight: CGRect?
    var name: String = ""
}

enum NotchClassification: Equatable {
    /// Camera housing confirmed: island anchors to the middle of the gap.
    case confirmed(gapMinX: CGFloat, gapMaxX: CGFloat, bandBottomY: CGFloat)
    /// No notch: zero top inset and no auxiliary areas.
    case absent
    /// API missing or data contradictory: treat as no notch (floating capsule).
    case unknown
}

enum IslandMode: Equatable {
    case notch
    case floating
}

struct IslandPlacement: Equatable {
    var frame: CGRect
    var mode: IslandMode
    var anchorX: CGFloat
    /// Upper edge the island hangs from; expansion grows downward from here.
    var topY: CGFloat
    /// Size of the camera housing (gap width × top inset) in notch mode.
    var notch: CGSize?
}

/// Pure geometry: classification of a screen and placement of the island.
/// All coordinates are global AppKit points (Y grows upward).
enum IslandPlacementEngine {
    static let floatingGap: CGFloat = 8
    static let minimumSize = CGSize(width: 60, height: 24)

    // MARK: Classification

    static func classify(_ s: ScreenSnapshot) -> NotchClassification {
        guard isUsable(s.frame), s.frame.width > 0, s.frame.height > 0 else { return .unknown }
        guard s.backingScale.isFinite, s.backingScale >= 1 else { return .unknown }
        guard let top = s.safeAreaTop, top.isFinite, top >= 0, top < s.frame.height else { return .unknown }

        let left = nonEmpty(s.auxiliaryTopLeft)
        let right = nonEmpty(s.auxiliaryTopRight)

        if top == 0 {
            return (left == nil && right == nil) ? .absent : .unknown
        }
        guard let rawLeft = left, let rawRight = right else { return .unknown }

        let tolerance = 1 / s.backingScale
        guard let l = align(rawLeft, in: s.frame, side: .left, tolerance: tolerance),
              let r = align(rawRight, in: s.frame, side: .right, tolerance: tolerance)
        else { return .unknown }

        let gapMinX = l.maxX
        let gapMaxX = r.minX
        guard gapMaxX - gapMinX > tolerance,
              gapMinX > s.frame.minX,
              gapMaxX < s.frame.maxX
        else { return .unknown }

        return .confirmed(gapMinX: gapMinX, gapMaxX: gapMaxX, bandBottomY: s.frame.maxY - top)
    }

    private enum Side { case left, right }

    /// Accepts the auxiliary rect either in global coordinates or relative to
    /// the screen origin, clips it to the frame and checks it hugs its corner.
    private static func align(_ rect: CGRect, in frame: CGRect, side: Side, tolerance: CGFloat) -> CGRect? {
        let candidates = [rect, rect.offsetBy(dx: frame.minX, dy: frame.minY)]
        for candidate in candidates {
            guard isUsable(candidate) else { continue }
            let clipped = candidate.intersection(frame)
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { continue }
            // Clipping must not have cut away a meaningful part of the rect.
            guard abs(clipped.width - candidate.width) <= tolerance,
                  abs(clipped.height - candidate.height) <= tolerance else { continue }
            let topOK = abs(clipped.maxY - frame.maxY) <= tolerance
            let edgeOK: Bool
            switch side {
            case .left: edgeOK = abs(clipped.minX - frame.minX) <= tolerance
            case .right: edgeOK = abs(clipped.maxX - frame.maxX) <= tolerance
            }
            if topOK && edgeOK { return clipped }
        }
        return nil
    }

    // MARK: Placement

    static func place(
        _ s: ScreenSnapshot,
        size desired: CGSize,
        menuBarThickness: CGFloat
    ) -> IslandPlacement? {
        guard desired.width.isFinite, desired.height.isFinite,
              desired.width > 0, desired.height > 0 else { return nil }
        guard isUsable(s.frame), isUsable(s.visibleFrame) else { return nil }

        let work = s.visibleFrame.intersection(s.frame)
        guard !work.isNull, work.width > 0, work.height > 0 else { return nil }

        let scale = (s.backingScale.isFinite && s.backingScale >= 1) ? s.backingScale : 1
        let reserved = max(menuBarThickness.isFinite ? menuBarThickness : 0, 0)
        var top = min(work.maxY, s.frame.maxY - reserved)

        let anchorX: CGFloat
        let mode: IslandMode
        var notch: CGSize?
        switch classify(s) {
        case let .confirmed(gapMinX, gapMaxX, bandBottomY):
            // The island grows out of the camera housing: its top edge is the
            // physical top of the screen, centred on the housing.
            anchorX = (gapMinX + gapMaxX) / 2
            top = s.frame.maxY
            notch = CGSize(width: gapMaxX - gapMinX, height: s.frame.maxY - bandBottomY)
            mode = .notch
        case .absent, .unknown:
            anchorX = s.frame.midX
            top -= floatingGap
            mode = .floating
        }

        let side = mode == .notch ? s.frame : work
        let maxWidth = 2 * min(anchorX - side.minX, side.maxX - anchorX)
        let maxHeight = top - work.minY
        let width = min(desired.width, maxWidth)
        let height = min(desired.height, maxHeight)
        guard width >= minimumSize.width, height >= minimumSize.height else { return nil }

        let raw = CGRect(x: anchorX - width / 2, y: top - height, width: width, height: height)
        let snapped = snapInward(raw, scale: scale)
        guard snapped.width >= minimumSize.width, snapped.height >= minimumSize.height else { return nil }
        return IslandPlacement(frame: snapped, mode: mode, anchorX: anchorX, topY: snapped.maxY, notch: notch)
    }

    /// Rounds a rect inward to the physical pixel grid of the screen.
    static func snapInward(_ r: CGRect, scale: CGFloat) -> CGRect {
        let minX = (r.minX * scale).rounded(.up) / scale
        let maxX = (r.maxX * scale).rounded(.down) / scale
        let minY = (r.minY * scale).rounded(.up) / scale
        let maxY = (r.maxY * scale).rounded(.down) / scale
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    // MARK: Helpers

    static func isUsable(_ r: CGRect) -> Bool {
        !r.isNull && !r.isInfinite
            && r.origin.x.isFinite && r.origin.y.isFinite
            && r.width.isFinite && r.height.isFinite
            && r.width >= 0 && r.height >= 0
    }

    private static func nonEmpty(_ r: CGRect?) -> CGRect? {
        guard let r, isUsable(r), r.width > 0, r.height > 0 else { return nil }
        return r
    }
}
