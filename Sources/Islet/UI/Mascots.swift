import SwiftUI

/// Characters that can live next to the notch.
enum MascotKind: String, CaseIterable, Identifiable {
    case cat, dog, fox, bunny, bear, panda, frog, penguin
    var id: String { rawValue }
    var titleKey: String { "mascot.\(rawValue)" }
}

/// A little animal that follows the cursor with its eyes, blinks, bobs to
/// music and falls asleep when you're away.
struct MascotView: View {
    var size: CGFloat
    /// Settings previews pass a kind explicitly and don't track the cursor.
    var kind: MascotKind?
    var interactive = true
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var cursor: CursorTracker
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var a11y: AccessibilityState

    var body: some View {
        let kind = self.kind ?? model.mascot
        TimelineView(.periodic(from: .now, by: interactive ? 0.25 : 3600)) { ctx in
            let now = ctx.date.timeIntervalSinceReferenceDate
            let asleep = interactive && ctx.date.timeIntervalSince(cursor.lastMove) > 60
            let blink = interactive && !asleep && Int(now * 4) % 17 == 0
            let dancing = interactive && media.track?.playing == true && !a11y.reduceMotion
            let bob: CGFloat = dancing ? CGFloat(sin(now * 9)) * 1.4 : 0
            let look: CGPoint = interactive ? lookDirection() : .zero
            Canvas { g, sz in
                MascotPainter.draw(kind, in: &g, side: sz.width, look: look, eyesClosed: asleep || blink)
                if asleep {
                    g.draw(Text(verbatim: "z").font(.system(size: sz.width * 0.35, weight: .bold)).foregroundColor(.white),
                           at: CGPoint(x: sz.width * 1.0, y: sz.width * 0.1))
                }
            }
            .frame(width: size, height: size)
            .offset(y: bob)
        }
        .accessibilityHidden(true)
    }

    /// Unit vector from the mascot toward the pointer (y down).
    private func lookDirection() -> CGPoint {
        let dx = cursor.location.x - cursor.anchor.x
        let dy = cursor.anchor.y - cursor.location.y
        let len = max(1, sqrt(dx * dx + dy * dy))
        return CGPoint(x: dx / len, y: dy / len)
    }
}

/// Vector drawings of every character, in a unit square scaled by `side`.
enum MascotPainter {
    private struct Eyes {
        var left: CGPoint
        var right: CGPoint
        var pupil: Color = .black
        /// White eyeball behind the pupil (frog, panda).
        var sclera: CGFloat = 0
        var closedColor: Color = .black
    }

    static func draw(_ kind: MascotKind, in g: inout GraphicsContext, side s: CGFloat, look: CGPoint, eyesClosed: Bool) {
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
        }
        func oval(_ rect: CGRect, _ c: Color) { g.fill(Path(ellipseIn: rect), with: .color(c)) }
        func poly(_ pts: [(CGFloat, CGFloat)], _ c: Color) {
            var p = Path()
            p.addLines(pts.map { CGPoint(x: $0.0 * s, y: $0.1 * s) })
            p.closeSubpath()
            g.fill(p, with: .color(c))
        }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

        let pink = Color(red: 0.96, green: 0.6, blue: 0.66)
        var eyes: Eyes

        switch kind {
        case .cat:
            poly([(0.14, 0.42), (0.2, 0.06), (0.44, 0.26)], .white)
            poly([(0.86, 0.42), (0.8, 0.06), (0.56, 0.26)], .white)
            oval(r(0.1, 0.22, 0.8, 0.68), .white)
            poly([(0.47, 0.68), (0.53, 0.68), (0.5, 0.72)], pink)
            eyes = Eyes(left: pt(0.36, 0.55), right: pt(0.64, 0.55))

        case .dog:
            let fur = Color(red: 0.96, green: 0.9, blue: 0.82)
            let ear = Color(red: 0.62, green: 0.41, blue: 0.25)
            oval(r(0.14, 0.2, 0.72, 0.72), fur)
            oval(r(0.0, 0.2, 0.26, 0.52), ear)
            oval(r(0.74, 0.2, 0.26, 0.52), ear)
            oval(r(0.3, 0.58, 0.4, 0.3), .white)
            oval(r(0.41, 0.6, 0.18, 0.12), .black)
            eyes = Eyes(left: pt(0.36, 0.48), right: pt(0.64, 0.48))

        case .fox:
            let orange = Color(red: 0.95, green: 0.55, blue: 0.22)
            poly([(0.1, 0.44), (0.16, 0.04), (0.42, 0.28)], orange)
            poly([(0.9, 0.44), (0.84, 0.04), (0.58, 0.28)], orange)
            poly([(0.15, 0.13), (0.17, 0.05), (0.24, 0.12)], Color(white: 0.15))
            poly([(0.85, 0.13), (0.83, 0.05), (0.76, 0.12)], Color(white: 0.15))
            oval(r(0.1, 0.22, 0.8, 0.5), orange)
            poly([(0.1, 0.5), (0.9, 0.5), (0.5, 0.96)], orange)
            poly([(0.14, 0.56), (0.5, 0.94), (0.5, 0.66)], .white)
            poly([(0.86, 0.56), (0.5, 0.94), (0.5, 0.66)], .white)
            oval(r(0.45, 0.85, 0.1, 0.07), .black)
            eyes = Eyes(left: pt(0.35, 0.5), right: pt(0.65, 0.5))

        case .bunny:
            oval(r(0.22, -0.02, 0.18, 0.52), .white)
            oval(r(0.6, -0.02, 0.18, 0.52), .white)
            oval(r(0.27, 0.06, 0.08, 0.34), pink)
            oval(r(0.65, 0.06, 0.08, 0.34), pink)
            oval(r(0.12, 0.34, 0.76, 0.62), .white)
            poly([(0.46, 0.76), (0.54, 0.76), (0.5, 0.81)], pink)
            eyes = Eyes(left: pt(0.36, 0.63), right: pt(0.64, 0.63))

        case .bear:
            let brown = Color(red: 0.66, green: 0.45, blue: 0.29)
            let light = Color(red: 0.9, green: 0.78, blue: 0.62)
            oval(r(0.08, 0.12, 0.28, 0.28), brown)
            oval(r(0.64, 0.12, 0.28, 0.28), brown)
            oval(r(0.14, 0.18, 0.16, 0.16), light)
            oval(r(0.7, 0.18, 0.16, 0.16), light)
            oval(r(0.12, 0.22, 0.76, 0.72), brown)
            oval(r(0.32, 0.58, 0.36, 0.28), light)
            oval(r(0.43, 0.61, 0.14, 0.1), .black)
            eyes = Eyes(left: pt(0.36, 0.48), right: pt(0.64, 0.48))

        case .panda:
            let patch = Color(white: 0.28)
            oval(r(0.08, 0.12, 0.28, 0.28), patch)
            oval(r(0.64, 0.12, 0.28, 0.28), patch)
            oval(r(0.12, 0.2, 0.76, 0.74), .white)
            oval(r(0.22, 0.42, 0.24, 0.24), patch)
            oval(r(0.54, 0.42, 0.24, 0.24), patch)
            oval(r(0.43, 0.68, 0.14, 0.09), patch)
            eyes = Eyes(left: pt(0.34, 0.54), right: pt(0.66, 0.54), pupil: .white, closedColor: .white)

        case .frog:
            let green = Color(red: 0.45, green: 0.78, blue: 0.32)
            oval(r(0.12, 0.14, 0.34, 0.34), green)
            oval(r(0.54, 0.14, 0.34, 0.34), green)
            oval(r(0.04, 0.34, 0.92, 0.58), green)
            var smile = Path()
            smile.move(to: pt(0.3, 0.7))
            smile.addQuadCurve(to: pt(0.7, 0.7), control: pt(0.5, 0.84))
            g.stroke(smile, with: .color(Color(red: 0.16, green: 0.4, blue: 0.12)), lineWidth: max(1, s * 0.05))
            eyes = Eyes(left: pt(0.29, 0.31), right: pt(0.71, 0.31), sclera: 0.12,
                        closedColor: Color(red: 0.16, green: 0.4, blue: 0.12))

        case .penguin:
            oval(r(0.1, 0.14, 0.8, 0.8), Color(white: 0.3))
            oval(r(0.18, 0.34, 0.38, 0.54), .white)
            oval(r(0.44, 0.34, 0.38, 0.54), .white)
            poly([(0.4, 0.66), (0.6, 0.66), (0.5, 0.8)], Color(red: 1, green: 0.66, blue: 0.2))
            eyes = Eyes(left: pt(0.36, 0.53), right: pt(0.64, 0.53))
        }

        // Eyes: pupils shift a little toward the cursor.
        let shift = CGPoint(x: look.x * s * 0.05, y: look.y * s * 0.05)
        for c in [eyes.left, eyes.right] {
            if eyesClosed {
                var l = Path()
                l.move(to: CGPoint(x: c.x - s * 0.07, y: c.y + s * 0.01))
                l.addQuadCurve(to: CGPoint(x: c.x + s * 0.07, y: c.y + s * 0.01), control: CGPoint(x: c.x, y: c.y + s * 0.05))
                g.stroke(l, with: .color(eyes.closedColor), lineWidth: max(1, s * 0.05))
                continue
            }
            if eyes.sclera > 0 {
                let rr = eyes.sclera * s
                g.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)), with: .color(.white))
            }
            let p = CGPoint(x: c.x + shift.x, y: c.y + shift.y)
            g.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.06, y: p.y - s * 0.08, width: s * 0.12, height: s * 0.16)),
                   with: .color(eyes.pupil))
        }
    }
}
