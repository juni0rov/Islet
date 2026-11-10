import SwiftUI
import UniformTypeIdentifiers

// MARK: Shape

/// The island outline. In notch mode the top corners flare outward ("ears")
/// so the island looks like it pours out of the camera housing. The bottom
/// edge can ripple (music).
struct NotchShape: Shape {
    var mode: IslandMode
    var bottomRadius: CGFloat
    var earRadius: CGFloat = 10
    var waveAmplitude: CGFloat = 0
    var wavePhase: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(bottomRadius, AnimatablePair(waveAmplitude, wavePhase)) }
        set {
            bottomRadius = newValue.first
            waveAmplitude = newValue.second.first
            wavePhase = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let ear = mode == .notch ? min(earRadius, rect.width / 4) : 0
        let left = rect.minX + ear, right = rect.maxX - ear
        let r = min(bottomRadius, (right - left) / 2, rect.height / 2)
        let top = rect.minY, bottom = rect.maxY

        if mode == .notch {
            p.move(to: CGPoint(x: rect.minX, y: top))
            p.addQuadCurve(to: CGPoint(x: left, y: top + ear), control: CGPoint(x: left, y: top))
        } else {
            let tr = r
            p.move(to: CGPoint(x: left, y: top + tr))
            p.addQuadCurve(to: CGPoint(x: left + tr, y: top), control: CGPoint(x: left, y: top))
            p.addLine(to: CGPoint(x: right - tr, y: top))
            p.addQuadCurve(to: CGPoint(x: right, y: top + tr), control: CGPoint(x: right, y: top))
            p.addLine(to: CGPoint(x: right, y: bottom - r))
            addBottom(&p, left: left, right: right, bottom: bottom, r: r)
            p.addLine(to: CGPoint(x: left, y: top + tr))
            p.closeSubpath()
            return p
        }
        p.addLine(to: CGPoint(x: left, y: bottom - r))
        // Bottom-left corner, wavy bottom, bottom-right corner (drawn left → right).
        p.addQuadCurve(to: CGPoint(x: left + r, y: bottom), control: CGPoint(x: left, y: bottom))
        addWave(&p, from: left + r, to: right - r, y: bottom)
        p.addQuadCurve(to: CGPoint(x: right, y: bottom - r), control: CGPoint(x: right, y: bottom))
        p.addLine(to: CGPoint(x: right, y: top + ear))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: top), control: CGPoint(x: right, y: top))
        p.closeSubpath()
        return p
    }

    /// Floating capsule: right side going down, bottom right → left, then up.
    private func addBottom(_ p: inout Path, left: CGFloat, right: CGFloat, bottom: CGFloat, r: CGFloat) {
        p.addQuadCurve(to: CGPoint(x: right - r, y: bottom), control: CGPoint(x: right, y: bottom))
        addWave(&p, from: right - r, to: left + r, y: bottom)
        p.addQuadCurve(to: CGPoint(x: left, y: bottom - r), control: CGPoint(x: left, y: bottom))
    }

    private func addWave(_ p: inout Path, from x0: CGFloat, to x1: CGFloat, y: CGFloat) {
        guard waveAmplitude > 0.05, abs(x1 - x0) > 8 else {
            p.addLine(to: CGPoint(x: x1, y: y)); return
        }
        let steps = max(8, Int(abs(x1 - x0) / 4))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = x0 + (x1 - x0) * t
            let envelope = sin(.pi * t)            // calm at the corners
            let w = sin(wavePhase + x / 9) * 0.55 + sin(wavePhase * 1.7 + x / 4.3) * 0.45
            p.addLine(to: CGPoint(x: x, y: y + waveAmplitude * envelope * w))
        }
    }
}

// MARK: Transitions

private struct BlurFade: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        content
            .blur(radius: active ? 10 : 0)
            .opacity(active ? 0 : 1)
            .scaleEffect(active ? 0.94 : 1, anchor: .top)
    }
}

extension AnyTransition {
    /// Content melts in as the island grows and melts out as it shrinks.
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
                .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.06)),
            removal: .modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
                .animation(.easeOut(duration: 0.14))
        )
    }
}

// MARK: Root

struct IslandRootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var a11y: AccessibilityState
    @EnvironmentObject var interaction: IslandInteraction
    @EnvironmentObject var activity: ActivityCenter
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var timer: TimerModel
    @EnvironmentObject var weather: WeatherService

    var body: some View {
        let state = interaction.state
        let current = activity.current
        let size = model.islandSize(state: state, activity: current)
        let open = state != .compact
        let radius: CGFloat = open ? 30 : (current != nil ? 24 : (model.placementMode == .notch ? 9 : 18))
        let playing = media.track?.playing == true && !a11y.reduceMotion

        ZStack(alignment: .top) {
            IslandBackground(mode: model.placementMode, radius: radius, size: size,
                             band: model.bandHeight, waving: playing,
                             amplitude: open ? 1.2 : (current != nil ? 2.4 : 2.0))
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(open || current != nil ? 0.45 : 0), radius: 18, y: 10)

            Group {
                if open {
                    ExpandedView().transition(.islandContent).id("expanded")
                } else if let current {
                    ActivityView(activity: current).transition(.islandContent).id(current.id)
                } else {
                    CompactView().transition(.islandContent).id("compact")
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(NotchShape(mode: model.placementMode, bottomRadius: radius))

            if model.dropTargeted {
                NotchShape(mode: model.placementMode, bottomRadius: radius)
                    .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, model.placementMode == .notch ? 0 : 0)
        .animation(a11y.spring(0.46, damping: 0.78), value: size)
        .animation(a11y.spring(0.46, damping: 0.78), value: radius)
        .environment(\.layoutDirection, language.layoutDirection)
        .environment(\.locale, language.locale)
        .onDrop(of: [UTType.fileURL], isTargeted: Binding(
            get: { model.dropTargeted },
            set: { targeted in
                model.dropTargeted = targeted
                if targeted {
                    model.selectedModule = .shelf
                    if interaction.state != .expanded { interaction.expand(keyboard: false) }
                }
            })
        ) { providers in
            model.selectedModule = .shelf
            return model.shelf.accept(providers)
        }
        .onExitCommand { interaction.escape() }
    }
}

/// Island fill: near-black at the notch, flowing into the theme below.
/// In floating mode it is glass. The bottom edge ripples while music plays.
private struct IslandBackground: View {
    var mode: IslandMode
    var radius: CGFloat
    var size: CGSize
    var band: CGFloat
    var waving: Bool
    var amplitude: CGFloat
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var a11y: AccessibilityState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !waving)) { ctx in
            let phase = waving ? CGFloat(ctx.date.timeIntervalSinceReferenceDate * 5.5) : 0
            let shape = NotchShape(mode: mode, bottomRadius: radius,
                                   waveAmplitude: waving ? amplitude : 0, wavePhase: phase)
            ZStack {
                if mode == .floating && !a11y.reduceTransparency {
                    VisualEffectBlur(material: .hudWindow).clipShape(shape)
                    shape.fill(theme.tokens.islandBody.color.opacity(theme.tokens.glassOpacity))
                } else {
                    shape.fill(theme.tokens.islandBody.color)
                }
                if mode == .notch {
                    // Opaque near-black at the camera housing, easing into the theme.
                    shape.fill(LinearGradient(
                        stops: [.init(color: .black, location: 0),
                                .init(color: .black, location: min(0.95, band / max(size.height, 1))),
                                .init(color: .black.opacity(0), location: min(1, (band + 12) / max(size.height, 1)))],
                        startPoint: .top, endPoint: .bottom))
                }
                shape.stroke(
                    LinearGradient(colors: [.white.opacity(0), theme.tokens.stroke.color.opacity(a11y.increaseContrast ? 0.9 : 0.22)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: a11y.increaseContrast ? 1.5 : 0.8)
            }
        }
    }
}

// MARK: Compact

struct CompactView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var interaction: IslandInteraction
    @EnvironmentObject var timer: TimerModel
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var weather: WeatherService

    var body: some View {
        Group {
            if model.placementMode == .notch {
                HStack(spacing: 0) {
                    leftWing.padding(.leading, 18)
                        .frame(width: model.wingWidth + AppModel.earRadius, alignment: .leading)
                    Spacer(minLength: 0)
                    rightWing.padding(.trailing, 18)
                        .frame(width: model.wingWidth + AppModel.earRadius, alignment: .trailing)
                }
                .frame(height: model.bandHeight)
            } else {
                HStack(spacing: 10) {
                    leftWing
                    Spacer(minLength: 4)
                    rightWing
                }
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
        .contentShape(Rectangle())
        .onTapGesture { interaction.click() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(language.t("a11y.expand")))
        .accessibilityAction { interaction.click() }
    }

    @ViewBuilder private var leftWing: some View {
        switch model.summary {
        case .timer:
            HStack(spacing: 5) {
                Image(systemName: "timer").foregroundStyle(.orange)
                Text(verbatim: timer.finished ? "0:00" : TimerModel.format(timer.remaining))
            }
        case .media:
            ArtworkView(image: media.artwork, size: 20, radius: 5)
        case .idle:
            HStack(spacing: 6) {
                if model.showMascot {
                    MascotView(size: 20)
                } else if model.temperatureOnLeft, let t = model.idleTemperature {
                    Image(systemName: weather.symbol).symbolRenderingMode(.multicolor)
                    Text(verbatim: t)
                }
            }
        }
    }

    @ViewBuilder private var rightWing: some View {
        switch model.summary {
        case .timer:
            ProgressRing(progress: timer.progress, color: .orange).frame(width: 16, height: 16)
        case .media:
            AudioBars(playing: media.track?.playing == true).frame(width: 22, height: 14)
        case .idle:
            HStack(spacing: 6) {
                if model.showTime {
                    TimelineView(.everyMinute) { ctx in
                        Text(verbatim: ctx.date.formatted(.dateTime.hour().minute().locale(language.locale)))
                    }
                }
                if model.showMascot, let t = model.idleTemperature {
                    Text(verbatim: t).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

// MARK: Activity (toast)

struct ActivityView: View {
    let activity: IslandActivity
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var interaction: IslandInteraction
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        VStack(spacing: 0) {
            if model.placementMode == .notch { Color.clear.frame(height: model.bandHeight - 4) }
            HStack(spacing: 12) {
                Group {
                    if let image = activity.image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: activity.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(activity.tint)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(activity.subtitle).font(.system(size: 11.5))
                        .foregroundStyle(theme.tokens.islandSecondary.color).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.tokens.islandPrimary.color)
            .padding(.horizontal, 26)
            .frame(maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { interaction.click() }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Small pieces

struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(red: 0.95, green: 0.45, blue: 0.4), Color(red: 0.35, green: 0.2, blue: 0.5)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Equaliser bars; they move only while something plays.
struct AudioBars: View {
    var playing: Bool
    var color: Color = .white
    @EnvironmentObject var a11y: AccessibilityState

    static func barHeight(_ i: Int, t: Double, playing: Bool) -> CGFloat {
        guard playing else { return 4 }
        let speed = 5 + Double(i) * 1.3
        let level = 0.35 + 0.65 * abs(sin(t * speed + Double(i) * 1.1))
        return CGFloat(max(3, 14 * level))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !playing || a11y.reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(color).frame(width: 2.6).frame(height: Self.barHeight(i, t: t, playing: playing))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct ProgressRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// A tiny cat that follows the cursor, blinks, dances to music and naps.
struct MascotView: View {
    var size: CGFloat
    @EnvironmentObject var cursor: CursorTracker
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var a11y: AccessibilityState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let now = ctx.date.timeIntervalSinceReferenceDate
            let asleep = ctx.date.timeIntervalSince(cursor.lastMove) > 60
            let blink = !asleep && Int(now * 4) % 17 == 0
            let dancing = media.track?.playing == true && !a11y.reduceMotion
            let bob: CGFloat = dancing ? CGFloat(sin(now * 9)) * 1.4 : 0
            Canvas { g, sz in
                let s = sz.width
                let head = CGRect(x: s * 0.1, y: s * 0.22, width: s * 0.8, height: s * 0.68)
                var ears = Path()
                ears.move(to: CGPoint(x: s * 0.14, y: s * 0.42))
                ears.addLine(to: CGPoint(x: s * 0.2, y: s * 0.06))
                ears.addLine(to: CGPoint(x: s * 0.44, y: s * 0.26))
                ears.move(to: CGPoint(x: s * 0.86, y: s * 0.42))
                ears.addLine(to: CGPoint(x: s * 0.8, y: s * 0.06))
                ears.addLine(to: CGPoint(x: s * 0.56, y: s * 0.26))
                g.fill(ears, with: .color(.white))
                g.fill(Path(ellipseIn: head), with: .color(.white))
                // Eyes look toward the cursor.
                let dx = cursor.location.x - cursor.anchor.x
                let dy = cursor.anchor.y - cursor.location.y
                let len = max(1, sqrt(dx * dx + dy * dy))
                let off = CGPoint(x: dx / len * s * 0.05, y: dy / len * s * 0.05)
                for ex in [s * 0.36, s * 0.64] {
                    let c = CGPoint(x: ex + off.x, y: s * 0.55 + off.y)
                    if asleep || blink {
                        var l = Path()
                        l.move(to: CGPoint(x: ex - s * 0.07, y: s * 0.56))
                        l.addQuadCurve(to: CGPoint(x: ex + s * 0.07, y: s * 0.56), control: CGPoint(x: ex, y: s * 0.6))
                        g.stroke(l, with: .color(.black), lineWidth: max(1, s * 0.05))
                    } else {
                        g.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.06, y: c.y - s * 0.08, width: s * 0.12, height: s * 0.16)),
                               with: .color(.black))
                    }
                }
                var nose = Path()
                nose.move(to: CGPoint(x: s * 0.47, y: s * 0.68))
                nose.addLine(to: CGPoint(x: s * 0.53, y: s * 0.68))
                nose.addLine(to: CGPoint(x: s * 0.5, y: s * 0.72))
                g.fill(nose, with: .color(Color(red: 0.95, green: 0.55, blue: 0.6)))
                if asleep {
                    g.draw(Text("z").font(.system(size: s * 0.35, weight: .bold)).foregroundColor(.white),
                           at: CGPoint(x: s * 1.0, y: s * 0.1))
                }
            }
            .frame(width: size, height: size)
            .offset(y: bob)
        }
        .accessibilityHidden(true)
    }
}
