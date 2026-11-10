import CoreGraphics
import Testing
#if !ISLET_LOCAL_TESTS
@testable import Islet
#endif

/// Synthetic geometry: notch / no notch / unknown, negative coordinates,
/// vertical arrangements, 1× and 2×, corrupted snapshots.
@Suite struct GeometryTests {
    static let menuBar: CGFloat = 24

    /// 14" MacBook Pro-like screen, origin configurable for multi-display.
    static func notched(origin: CGPoint = .zero, scale: CGFloat = 2, localAux: Bool = false) -> ScreenSnapshot {
        let frame = CGRect(x: origin.x, y: origin.y, width: 1512, height: 982)
        let leftGlobal = CGRect(x: frame.minX, y: frame.maxY - 32, width: 662, height: 32)
        let rightGlobal = CGRect(x: frame.minX + 850, y: frame.maxY - 32, width: 662, height: 32)
        let off = localAux ? CGPoint(x: -frame.minX, y: -frame.minY) : .zero
        return ScreenSnapshot(
            displayID: 1, frame: frame,
            visibleFrame: CGRect(x: frame.minX, y: frame.minY, width: 1512, height: 982 - 38),
            backingScale: scale, safeAreaTop: 32,
            auxiliaryTopLeft: leftGlobal.offsetBy(dx: off.x, dy: off.y),
            auxiliaryTopRight: rightGlobal.offsetBy(dx: off.x, dy: off.y))
    }

    static func plain(origin: CGPoint = .zero, scale: CGFloat = 1) -> ScreenSnapshot {
        let frame = CGRect(x: origin.x, y: origin.y, width: 1920, height: 1080)
        return ScreenSnapshot(displayID: 2, frame: frame,
                              visibleFrame: CGRect(x: frame.minX, y: frame.minY + 70, width: 1920, height: 1080 - 70 - 25),
                              backingScale: scale, safeAreaTop: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil)
    }

    @Test func confirmsNotch() {
        guard case let .confirmed(minX, maxX, band) = IslandPlacementEngine.classify(Self.notched()) else {
            Issue.record("expected confirmed notch"); return
        }
        #expect(minX == 662)
        #expect(maxX == 850)
        #expect(band == 950)
    }

    @Test func notchPlacementGrowsOutOfTheHousing() throws {
        let s = Self.notched()
        let p = try #require(IslandPlacementEngine.place(s, size: CGSize(width: 380, height: 32), menuBarThickness: Self.menuBar))
        #expect(p.mode == .notch)
        let pixel = 1 / s.backingScale
        #expect(abs(p.frame.midX - 756) <= pixel)      // centred on the housing
        #expect(p.frame.maxY == s.frame.maxY)          // flush with the top edge
        #expect(p.notch == CGSize(width: 188, height: 32))
        #expect(p.frame.width >= 188)                  // wider than the housing
    }

    @Test func expandedGrowsDownKeepingTopAndAxis() throws {
        let s = Self.notched()
        let c = try #require(IslandPlacementEngine.place(s, size: CGSize(width: 236, height: 34), menuBarThickness: Self.menuBar))
        let e = try #require(IslandPlacementEngine.place(s, size: CGSize(width: 480, height: 268), menuBarThickness: Self.menuBar))
        #expect(c.frame.maxY == e.frame.maxY)
        #expect(abs(c.frame.midX - e.frame.midX) <= 0.5)
        #expect(e.frame.minY < c.frame.minY)
    }

    @Test func acceptsScreenLocalAuxiliaryAreasOnOffsetDisplay() {
        let s = Self.notched(origin: CGPoint(x: -1512, y: 300), localAux: true)
        guard case let .confirmed(minX, maxX, _) = IslandPlacementEngine.classify(s) else {
            Issue.record("expected confirmed"); return
        }
        #expect(minX == CGFloat(-850))
        #expect(maxX == CGFloat(-662))
    }

    @Test(arguments: [CGPoint(x: -1920, y: -1080), CGPoint(x: 0, y: 982), CGPoint(x: 2000, y: -500)])
    func floatingOnPlainScreensAnywhere(origin: CGPoint) throws {
        let s = Self.plain(origin: origin)
        #expect(IslandPlacementEngine.classify(s) == .absent)
        let p = try #require(IslandPlacementEngine.place(s, size: CGSize(width: 236, height: 34), menuBarThickness: Self.menuBar))
        #expect(p.mode == .floating)
        #expect(p.frame.midX == s.frame.midX)
        #expect(p.frame.maxY <= s.visibleFrame.maxY - IslandPlacementEngine.floatingGap)
        #expect(s.frame.contains(p.frame))
    }

    @Test(arguments: [CGFloat(1), 2, 3])
    func snapsInwardToPixelGrid(scale: CGFloat) {
        let r = IslandPlacementEngine.snapInward(CGRect(x: 10.3, y: 20.7, width: 100.1, height: 33.3), scale: scale)
        #expect((r.minX * scale).rounded() == r.minX * scale)
        #expect((r.maxY * scale).rounded() == r.maxY * scale)
        #expect(r.minX >= 10.3 && r.maxX <= 110.4)
    }

    @Test func unknownWhenApiMissing() {
        var s = Self.plain()
        s.safeAreaTop = nil
        #expect(IslandPlacementEngine.classify(s) == .unknown)
        #expect(IslandPlacementEngine.place(s, size: CGSize(width: 200, height: 34), menuBarThickness: 24)?.mode == .floating)
    }

    @Test func unknownWhenOneAreaMissing() {
        var s = Self.notched()
        s.auxiliaryTopRight = nil
        #expect(IslandPlacementEngine.classify(s) == .unknown)
    }

    @Test func unknownWhenAreasOverlap() {
        var s = Self.notched()
        s.auxiliaryTopRight = CGRect(x: 500, y: 950, width: 1012, height: 32)
        #expect(IslandPlacementEngine.classify(s) == .unknown)
    }

    @Test func unknownWhenAreasDoNotTouchCorners() {
        var s = Self.notched()
        s.auxiliaryTopLeft = CGRect(x: 40, y: 900, width: 600, height: 32)
        #expect(IslandPlacementEngine.classify(s) == .unknown)
    }

    @Test func unknownWhenZeroInsetButAreasPresent() {
        var s = Self.notched()
        s.safeAreaTop = 0
        #expect(IslandPlacementEngine.classify(s) == .unknown)
    }

    @Test func corruptedSnapshotsDoNotCrash() {
        let bad: [ScreenSnapshot] = [
            ScreenSnapshot(displayID: nil, frame: .null, visibleFrame: .null, backingScale: 2, safeAreaTop: 0),
            ScreenSnapshot(displayID: nil, frame: CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10),
                           visibleFrame: .zero, backingScale: .infinity, safeAreaTop: .nan),
            ScreenSnapshot(displayID: nil, frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                           visibleFrame: CGRect(x: 5000, y: 5000, width: 10, height: 10), backingScale: 0, safeAreaTop: -4),
            ScreenSnapshot(displayID: nil, frame: .infinite, visibleFrame: .infinite, backingScale: 1, safeAreaTop: 0)
        ]
        for s in bad {
            _ = IslandPlacementEngine.classify(s)
            #expect(IslandPlacementEngine.place(s, size: CGSize(width: 200, height: 34), menuBarThickness: 24) == nil)
        }
    }

    @Test func hiddenWhenNoRoom() {
        var s = Self.plain()
        s.visibleFrame = CGRect(x: 0, y: 1000, width: 1920, height: 30)
        #expect(IslandPlacementEngine.place(s, size: CGSize(width: 236, height: 34), menuBarThickness: 24) == nil)
    }

    @Test func widthClampedToNearestSideOfWorkArea() throws {
        var s = Self.plain()
        s.visibleFrame = CGRect(x: 0, y: 0, width: 1100, height: 1050) // dock on the right
        let p = try #require(IslandPlacementEngine.place(s, size: CGSize(width: 900, height: 34), menuBarThickness: 24))
        #expect(p.frame.maxX <= 1100)
        #expect(p.frame.midX == 960 || abs(p.frame.midX - 960) <= 1)
    }

    @Test func choosesNotchedScreenThenPrimary() {
        let plain = Self.plain(origin: CGPoint(x: 0, y: 0))
        let notch = Self.notched(origin: CGPoint(x: 1920, y: 0))
        #expect(DisplayGeometryProvider.chooseScreen(from: [plain, notch], preferredID: nil)?.displayID == 1)
        #expect(DisplayGeometryProvider.chooseScreen(from: [plain, notch], preferredID: 2)?.displayID == 2)
        #expect(DisplayGeometryProvider.chooseScreen(from: [plain], preferredID: 99)?.displayID == 2)
        #expect(DisplayGeometryProvider.chooseScreen(from: [], preferredID: nil) == nil)
    }
}
