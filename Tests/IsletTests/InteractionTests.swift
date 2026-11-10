import Foundation
import Testing
#if !ISLET_LOCAL_TESTS
@testable import Islet
#endif

/// Deterministic scheduler: blocks run only when `advance` passes their time.
final class ManualScheduler: InteractionScheduler {
    private var now: TimeInterval = 0
    private var items: [(id: Int, at: TimeInterval, block: () -> Void)] = []
    private var nextID = 0

    func after(_ delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellation {
        nextID += 1
        let id = nextID
        items.append((id, now + delay, block))
        return Cancellation { [weak self] in self?.items.removeAll { $0.id == id } }
    }

    func advance(_ dt: TimeInterval) {
        now += dt
        let due = items.filter { $0.at <= now }.sorted { $0.at < $1.at }
        items.removeAll { $0.at <= now }
        due.forEach { $0.block() }
    }
}

@Suite struct InteractionTests {
    func make() -> (IslandInteraction, ManualScheduler) {
        let s = ManualScheduler()
        let i = IslandInteraction(scheduler: s)
        i.previewDelay = 0.2
        i.leaveDelay = 0.25
        return (i, s)
    }

    @Test func quickPassDoesNotPreview() {
        let (i, s) = make()
        i.pointerEntered()
        s.advance(0.1)
        i.pointerExited()
        s.advance(1)
        #expect(i.state == .compact)
        #expect(!i.hasPendingTimers)
    }

    @Test func hoverPreviewsAfterDelayAndClosesAfterLeave() {
        let (i, s) = make()
        i.pointerEntered()
        s.advance(0.21)
        #expect(i.state == .preview)
        i.pointerExited()
        s.advance(0.1)
        #expect(i.state == .preview)
        s.advance(0.2)
        #expect(i.state == .compact)
    }

    @Test func movingBetweenCapsuleAndContentKeepsPreview() {
        let (i, s) = make()
        i.pointerEntered(); s.advance(0.3)
        i.pointerExited(); s.advance(0.05)
        i.pointerEntered(); s.advance(1)
        #expect(i.state == .preview)
    }

    @Test func previewCanBeDisabled() {
        let (i, s) = make()
        i.previewEnabled = false
        i.pointerEntered(); s.advance(2)
        #expect(i.state == .compact)
    }

    @Test func clickPinsAndSecondClickCollapses() {
        let (i, s) = make()
        i.click()
        #expect(i.state == .expanded)
        i.pointerExited(); s.advance(2)
        #expect(i.state == .expanded)
        i.click()
        #expect(i.state == .compact)
    }

    @Test func escapeOnlyCollapsesExpanded() {
        let (i, _) = make()
        i.escape()
        #expect(i.state == .compact)
        i.toggleFromMenu()
        #expect(i.state == .expanded)
        #expect(i.keyboardFocusRequested)
        i.escape()
        #expect(i.state == .compact)
        #expect(!i.keyboardFocusRequested)
    }

    @Test func newActionInterruptsPendingTransition() {
        let (i, s) = make()
        i.pointerEntered()
        i.click()            // before the preview fires
        s.advance(1)
        #expect(i.state == .expanded)
        #expect(!i.hasPendingTimers)
    }

    @Test func resetCancelsEverything() {
        let (i, s) = make()
        i.pointerEntered(); s.advance(0.3)
        i.reset()
        s.advance(1)
        #expect(i.state == .compact)
        #expect(!i.pointerInside)
    }

    @Test func clickInsidePreviewPins() {
        let (i, s) = make()
        i.pointerEntered(); s.advance(0.3)
        #expect(i.state == .preview)
        i.clickedInside()
        #expect(i.state == .expanded)
        i.pointerExited(); s.advance(2)
        #expect(i.state == .expanded)
    }

    @Test func clickOutsideCloses() {
        let (i, _) = make()
        i.click()
        i.clickedOutside()
        #expect(i.state == .compact)
        i.clickedOutside()
        #expect(i.state == .compact)
    }
}

@Suite struct ToolsTests {
    @Test(arguments: [("2+2", 4.0), ("2400*15%", 360.0), ("200+15%", 230.0), ("(1+2)*3", 9.0),
                      ("2^10", 1024.0), ("10/4", 2.5), ("-3+5", 2.0), ("1,5*2", 3.0)])
    func calculator(input: String, expected: Double) {
        #expect(Calculator.evaluate(input) == expected)
    }

    @Test(arguments: ["", "hello", "2+", "(1+2", "1/0", "rm -rf", "12"])
    func calculatorRejectsNonsense(input: String) {
        #expect(Calculator.evaluate(input) == nil)
    }

    @Test func fixesKeyboardLayout() {
        #expect(TextTools.fixLayout("ghbdtn") == "привет")
        #expect(TextTools.fixLayout("руддщ") == "hello")
        #expect(TextTools.fixLayout("Ghbdtn? rfr ltkf&") == "Привет, как дела?")
    }

    @Test func transliterates() {
        #expect(TextTools.transliterate("Привет, Щука!") == "Privet, Shchuka!")
    }
}
