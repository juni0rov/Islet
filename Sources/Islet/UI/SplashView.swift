import AppKit
import SwiftUI

/// App mark: a glass capsule with a soft light — the "islet".
struct IsletMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: max(1, size * 0.02))
            Capsule()
                .fill(Color.black)
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: max(0.8, size * 0.012)))
                .overlay(alignment: .trailing) {
                    Circle()
                        .fill(Color(red: 0.62, green: 0.78, blue: 0.74))
                        .frame(width: size * 0.09, height: size * 0.09)
                        .padding(.trailing, size * 0.07)
                        .shadow(color: Color(red: 0.62, green: 0.78, blue: 0.74).opacity(0.8), radius: size * 0.04)
                }
                .frame(width: size * 0.62, height: size * 0.2)
                .offset(y: -size * 0.12)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SplashView: View {
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var a11y: AccessibilityState
    @State private var appeared = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        VStack(spacing: 14) {
            IsletMark(size: 72)
                .scaleEffect(appeared || a11y.reduceMotion ? 1 : 0.85)
            VStack(spacing: 4) {
                Text(verbatim: AppInfo.name)
                    .font(.system(size: 34, weight: .semibold))
                Text(language.t("splash.tagline"))
                    .font(.system(.subheadline))
                    .foregroundStyle(theme.tokens.textSecondary.color)
            }
            Capsule()
                .fill(theme.tokens.stroke.color.opacity(0.5))
                .frame(width: 40, height: 1)
            Text(language.t("splash.madeBy", AppInfo.author))
                .font(.system(.footnote).weight(.medium))
                .foregroundStyle(theme.tokens.textSecondary.color)
                .tracking(1.2)
        }
        .foregroundStyle(theme.tokens.textPrimary.color)
        .padding(.vertical, 28)
        .padding(.horizontal, 44)
        .frame(width: 340, height: 260)
        .background(GlassSurface(tokens: theme.tokens, shape: shape,
                                 reduceTransparency: a11y.reduceTransparency,
                                 increaseContrast: a11y.increaseContrast))
        .clipShape(shape)
        .environment(\.layoutDirection, language.layoutDirection)
        .onAppear {
            withAnimation(a11y.reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8)) { appeared = true }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shows the splash card for a moment at launch, then fades it out.
@MainActor
final class SplashController {
    private var panel: NSPanel?

    func show(model: AppModel, completion: @escaping () -> Void) {
        let size = NSSize(width: 340, height: 260)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        let view = SplashView()
            .environmentObject(model.language)
            .environmentObject(model.theme)
            .environmentObject(model.accessibility)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2 + 60))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        let fade = model.accessibility.reduceMotion ? 0.15 : 0.45
        NSAnimationContext.runAnimationGroup { $0.duration = fade; panel.animator().alphaValue = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = fade
                panel.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    panel.orderOut(nil)
                    self?.panel = nil
                    completion()
                }
            }
        }
    }
}
