import AppKit
import SwiftUI

// MARK: Shared tokens

enum Metrics {
    static let radiusCompact: CGFloat = 17
    static let radiusExpanded: CGFloat = 30
    static let radiusCard: CGFloat = 16
    static let radiusControl: CGFloat = 10
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 14
    static let shadowRadius: CGFloat = 18
}

enum Motion {
    static let preview: Double = 0.25   // 200–300 ms
    static let expand: Double = 0.38    // 300–450 ms
    static let collapse: Double = 0.25  // 200–300 ms

    static func duration(from: IslandState, to: IslandState) -> Double {
        if to == .expanded { return expand }
        if to == .preview { return preview }
        return collapse
    }
}

// MARK: Material

/// One native blur layer per panel.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.material = material
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
    }
}

struct IslandShape: Shape {
    var mode: IslandMode
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let top: CGFloat = mode == .notch ? min(6, radius) : radius
        return UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: radius,
            bottomTrailingRadius: radius, topTrailingRadius: top,
            style: .continuous
        ).path(in: rect)
    }
}

/// Base glass surface: blur + theme tint + decorative edge + visible border.
struct GlassSurface<S: InsettableShape>: View {
    var tokens: ThemeTokens
    var shape: S
    var reduceTransparency: Bool
    var increaseContrast: Bool
    var notchEdge: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            if reduceTransparency {
                shape.fill(tokens.panel.color)
                shape.fill(tokens.base.color.opacity(0.35))
            } else {
                VisualEffectBlur().clipShape(shape)
                shape.fill(tokens.base.color.opacity(tokens.glassOpacity))
                shape.fill(
                    LinearGradient(colors: [tokens.stroke.color.opacity(0.10), .clear],
                                   startPoint: .top, endPoint: .center)
                )
            }
            if notchEdge {
                // Opaque near-black at the camera housing, easing into the theme.
                LinearGradient(colors: [Color(white: 0.02), Color(white: 0.02).opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
                    .clipShape(shape)
            }
            shape.strokeBorder(
                increaseContrast ? tokens.controlBorder.color : tokens.stroke.color.opacity(0.45),
                lineWidth: increaseContrast ? 1.5 : 0.8
            )
        }
        .compositingGroup()
    }
}

// MARK: Card

struct IsletCard<Content: View>: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var a11y: AccessibilityState
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                    .fill(theme.tokens.panel.color.opacity(a11y.reduceTransparency ? 1 : 0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                    .strokeBorder(theme.tokens.stroke.color.opacity(a11y.increaseContrast ? 0.9 : 0.35),
                                  lineWidth: a11y.increaseContrast ? 1.2 : 0.6)
            )
    }
}

// MARK: Button

struct IsletButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, icon }
    var kind: Kind = .secondary
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        IsletButtonBody(configuration: configuration, kind: kind, selected: selected)
    }
}

private struct IsletButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: IsletButtonStyle.Kind
    let selected: Bool
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var a11y: AccessibilityState
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovering = false

    var body: some View {
        let t = theme.tokens
        let filled = kind == .primary || selected
        configuration.label
            .font(.system(.callout).weight(.medium))
            .foregroundStyle(filled ? t.panel.color : t.textPrimary.color)
            .padding(.horizontal, kind == .icon ? 8 : 12)
            .padding(.vertical, 6)
            .frame(minWidth: 28, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                    .fill(filled ? t.textPrimary.color : t.panel.color.opacity(hovering ? 1 : 0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                    .strokeBorder(t.controlBorder.color.opacity(a11y.increaseContrast ? 1 : 0.55), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusControl + 3, style: .continuous)
                    .strokeBorder(t.focus.color, lineWidth: a11y.increaseContrast ? 3 : 2)
                    .padding(-3)
                    .opacity(focused ? 1 : 0)
            )
            .scaleEffect(configuration.isPressed && !a11y.reduceMotion ? 0.96 : 1)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(a11y.reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: Toggle (switch with a symbol, so state is not colour-only)

struct IsletToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        IsletToggleBody(configuration: configuration)
    }
}

private struct IsletToggleBody: View {
    let configuration: ToggleStyleConfiguration
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let t = theme.tokens
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 10) {
                configuration.label.foregroundStyle(t.textPrimary.color)
                Spacer(minLength: 8)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? t.textPrimary.color : t.panel.color)
                    Capsule().strokeBorder(t.controlBorder.color, lineWidth: 1)
                    Circle()
                        .fill(configuration.isOn ? t.panel.color : t.textSecondary.color)
                        .overlay(Image(systemName: configuration.isOn ? "checkmark" : "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(configuration.isOn ? t.textPrimary.color : t.panel.color))
                        .padding(3)
                }
                .frame(width: 40, height: 22)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? Text(verbatim: "1") : Text(verbatim: "0"))
    }
}

// MARK: Progress

struct IsletProgressBar: View {
    var value: Double
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.tokens.textSecondary.color.opacity(0.25))
                Capsule().fill(theme.tokens.textPrimary.color)
                    .frame(width: max(4, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 5)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int(value * 100))%"))
    }
}

// MARK: Capsule chip

struct IsletChip: View {
    var symbol: String
    var text: String
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).imageScale(.small)
            Text(text).lineLimit(1)
        }
        .font(.system(.caption).weight(.semibold).monospacedDigit())
        .foregroundStyle(theme.tokens.textPrimary.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(theme.tokens.panel.color.opacity(0.9)))
        .overlay(Capsule().strokeBorder(theme.tokens.stroke.color.opacity(0.4), lineWidth: 0.6))
        .help(text)
    }
}
