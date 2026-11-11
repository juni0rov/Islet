import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var language: LanguageStore

    enum Tab: String, CaseIterable, Identifiable {
        case appearance, language, display, behavior, about
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .appearance: return "paintpalette"
            case .language: return "globe"
            case .display: return "display"
            case .behavior: return "cursorarrow.motionlines"
            case .about: return "info.circle"
            }
        }
    }

    @State private var tab: Tab
    @State private var sidebarVisible: Bool

    init(startTab: Tab = .appearance, sidebar: Bool = true) {
        _tab = State(initialValue: startTab)
        _sidebarVisible = State(initialValue: sidebar)
    }
    @EnvironmentObject var a11y: AccessibilityState

    private var motion: Animation { a11y.spring(0.42, damping: 0.86) }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                sidebar
                    .frame(width: 210)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider().transition(.opacity)
            }
            detail
        }
        .overlay(alignment: .topLeading) {
            // Sits next to the traffic lights and never moves, like Finder's.
            Button {
                withAnimation(motion) { sidebarVisible.toggle() }
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SidebarToggleStyle())
            .help(language.t("settings.sidebar"))
            .accessibilityLabel(Text(language.t("settings.sidebar")))
            .padding(.leading, 82)
            .padding(.top, 7)
        }
        .frame(minWidth: 560, minHeight: 460)
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.layoutDirection, language.layoutDirection)
        .environment(\.locale, language.locale)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Tab.allCases) { t in
                SidebarRow(title: language.t("settings.\(t.rawValue)"), symbol: t.symbol, selected: tab == t) {
                    withAnimation(motion) { tab = t }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 50)
        .frame(maxHeight: .infinity)
        .background(VisualEffectBlur(material: .sidebar).ignoresSafeArea())
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(language.t("settings.\(tab.rawValue)"))
                .font(.system(size: 20, weight: .semibold))
                .padding(.leading, sidebarVisible ? 24 : 124)
                .frame(height: 40)
                .padding(.top, 2)
                .id("title-\(tab.rawValue)")
                .transition(.opacity)
            Divider()
            ScrollView {
                Group {
                    switch tab {
                    case .appearance: AppearanceSettings()
                    case .language: LanguageSettings()
                    case .display: DisplaySettings()
                    case .behavior: BehaviorSettings()
                    case .about: AboutSettings()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(tab)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13.5))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.12 : (hover ? 0.06 : 0))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SidebarToggleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SidebarToggleBody(configuration: configuration)
    }
}

private struct SidebarToggleBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hover = false

    var body: some View {
        configuration.label
            .foregroundStyle(.secondary)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (hover ? 0.08 : 0))))
            .onHover { hover = $0 }
    }
}

// MARK: Appearance

private struct AppearanceSettings: View {
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var a11y: AccessibilityState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(language.t("appearance.theme")).font(.headline)
            HStack(spacing: 14) {
                ForEach(ThemeID.allCases) { id in
                    ThemeSwatch(id: id, selected: theme.themeID == id) { theme.select(id) }
                }
            }
            Toggle(isOn: $theme.allowWallpaper) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.t("appearance.wallpaper"))
                    Text(language.t("appearance.wallpaper.hint"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)

            Text(language.t("appearance.preview")).font(.headline)
            IslandPreviewCard()
            if a11y.reduceTransparency {
                Label(language.t("appearance.opaque"), systemImage: "circle.lefthalf.filled")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ThemeSwatch: View {
    let id: ThemeID
    let selected: Bool
    let action: () -> Void
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let t = id == theme.themeID ? theme.tokens : ThemeTokens.tokens(for: id)
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t.base.color)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(t.panel.color)
                        .overlay(Text(verbatim: "Aa").font(.system(.title3).weight(.semibold))
                            .foregroundStyle(t.textPrimary.color))
                        .padding(14)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(t.stroke.color.opacity(0.7), lineWidth: 1)
                }
                .frame(width: 130, height: 84)
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0)
                        .padding(-4)
                )
                HStack(spacing: 4) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    Text(language.t("theme.\(id.rawValue)"))
                }
                .font(.callout)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(language.t("theme.\(id.rawValue)")))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Live preview of the expanded island on a fixed backdrop.
private struct IslandPreviewCard: View {
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var a11y: AccessibilityState

    var body: some View {
        let t = theme.tokens
        ZStack {
            LinearGradient(colors: [Color(red: 0.55, green: 0.60, blue: 0.56), Color(red: 0.20, green: 0.24, blue: 0.24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(language.t("module.timer"), systemImage: "timer").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.up")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "24:59").font(.system(size: 30, weight: .semibold).monospacedDigit())
                    Text(language.plural("shelf.count", 3))
                        .font(.subheadline).foregroundStyle(t.textSecondary.color)
                    IsletProgressBar(value: 0.35)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t.panel.color))
            }
            .foregroundStyle(t.textPrimary.color)
            .padding(16)
            .frame(width: 340)
            .background(
                GlassSurface(tokens: t, shape: RoundedRectangle(cornerRadius: 26, style: .continuous),
                             reduceTransparency: true, increaseContrast: a11y.increaseContrast)
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(language.t("appearance.preview")))
    }
}

// MARK: Language

private struct LanguageSettings: View {
    @EnvironmentObject var language: LanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(selection: Binding(get: { language.selection }, set: { language.select($0) })) {
                Text(language.t("language.system")).tag(LanguageResolver.systemValue)
                ForEach(language.available, id: \.self) { tag in
                    Text(verbatim: language.autonym(tag)).tag(tag)
                }
            } label: {
                Text(language.t("settings.language"))
            }
            .pickerStyle(.radioGroup)
            Text(language.t("language.note"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Display

private struct DisplaySettings: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var language: LanguageStore
    @State private var screens: [ScreenSnapshot] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(language.t("display.choose"), selection: $model.preferredDisplayID) {
                Text(language.t("display.auto")).tag(UInt32(0))
                ForEach(screens, id: \.displayID) { s in
                    Text(verbatim: s.name.isEmpty ? "#\(s.displayID ?? 0)" : s.name).tag(s.displayID ?? 0)
                }
            }
            .frame(maxWidth: 360)
            Label(statusText, systemImage: statusSymbol)
                .font(.callout)
            Text(language.t("display.note"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 4)
            Text(language.t("fit.title")).font(.headline)
            Text(language.t("fit.hint"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            FitSlider(title: language.t("fit.width"), value: $model.fitWidth)
            FitSlider(title: language.t("fit.height"), value: $model.fitHeight)
            HStack {
                Button(language.t("fit.reset")) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        model.fitWidth = AppModel.defaultFit
                        model.fitHeight = AppModel.defaultFit
                    }
                }
                if model.placementMode != .notch {
                    Text(language.t("fit.noNotch")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { screens = DisplayGeometryProvider.snapshots() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = DisplayGeometryProvider.snapshots()
        }
    }

    private var statusText: String {
        if model.islandHidden { return language.t("display.status.hidden") }
        switch model.classification {
        case .confirmed: return language.t("display.status.notch")
        case .absent: return language.t("display.status.floating")
        case .unknown: return language.t("display.status.unknown")
        }
    }

    private var statusSymbol: String {
        if model.islandHidden { return "eye.slash" }
        if case .confirmed = model.classification { return "macbook" }
        return "capsule"
    }
}

/// Slider in 0.5 pt steps (one physical pixel on Retina) with − / + buttons
/// for exact nudging.
private struct FitSlider: View {
    let title: String
    @Binding var value: Double
    @EnvironmentObject var language: LanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: value.formatted(.number.precision(.fractionLength(1)).locale(language.locale)) + " pt")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button { nudge(-0.5) } label: { Image(systemName: "minus") }
                    .accessibilityLabel(Text(verbatim: "−0.5"))
                Slider(value: Binding(get: { value }, set: { value = ($0 * 2).rounded() / 2 }),
                       in: AppModel.fitRange)
                    .accessibilityLabel(Text(title))
                Button { nudge(0.5) } label: { Image(systemName: "plus") }
                    .accessibilityLabel(Text(verbatim: "+0.5"))
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: 420)
    }

    private func nudge(_ d: Double) {
        value = min(max(value + d, AppModel.fitRange.lowerBound), AppModel.fitRange.upperBound)
    }
}

// MARK: Behavior

private struct BehaviorSettings: View {
    @EnvironmentObject var a11y: AccessibilityState
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var weather: WeatherService
    @State private var cityDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(language.t("behavior.preview"), isOn: $model.previewEnabled).toggleStyle(.switch)
            VStack(alignment: .leading, spacing: 6) {
                Text(language.t("behavior.delay", Int(model.previewDelay * 1000)))
                Slider(value: $model.previewDelay, in: 0.1...1.0, step: 0.05)
                    .frame(maxWidth: 320)
                    .disabled(!model.previewEnabled)
                    .accessibilityValue(Text(language.t("behavior.delay", Int(model.previewDelay * 1000))))
            }
            Toggle(language.t("behavior.splash"), isOn: $model.showSplash).toggleStyle(.switch)
            Text(language.t("behavior.wings")).font(.headline)
            Toggle(language.t("behavior.mascot"), isOn: $model.showMascot).toggleStyle(.switch)
            if model.showMascot {
                Text(language.t("behavior.mascotPick")).font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: 4), alignment: .leading, spacing: 8) {
                    ForEach(MascotKind.allCases) { kind in
                        MascotChoice(kind: kind, selected: model.mascot == kind) {
                            withAnimation(a11y.spring(0.35, damping: 0.7)) { model.mascot = kind }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Toggle(language.t("behavior.time"), isOn: $model.showTime).toggleStyle(.switch)
            Toggle(language.t("behavior.temperature"), isOn: $model.showTemperature).toggleStyle(.switch)
            Text(language.t("behavior.wingsHint")).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle(language.t("behavior.toasts"), isOn: $model.showToasts).toggleStyle(.switch)
            Divider()
            Toggle(language.t("behavior.weather"), isOn: $weather.enabled).toggleStyle(.switch)
            HStack {
                Text(language.t("behavior.city"))
                TextField(WeatherService.cityFromTimeZone(), text: $cityDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .onSubmit { weather.city = cityDraft }
                Button(language.t("behavior.apply")) { weather.city = cityDraft }
            }
            .disabled(!weather.enabled)
            Text(language.t("weather.hint")).font(.caption).foregroundStyle(.secondary)
            Label(language.t("behavior.shortcut"), systemImage: "keyboard")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onAppear { cityDraft = weather.city }
    }
}

private struct MascotChoice: View {
    let kind: MascotKind
    let selected: Bool
    let action: () -> Void
    @EnvironmentObject var language: LanguageStore
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                MascotView(size: 30, kind: kind, interactive: false)
                    .frame(width: 56, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: selected ? 2.5 : 0))
                    .scaleEffect(selected ? 1.06 : (hover ? 1.03 : 1))
                Text(language.t(kind.titleKey)).font(.caption).lineLimit(1)
            }
            .frame(width: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .accessibilityLabel(Text(language.t(kind.titleKey)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: About

private struct AboutSettings: View {
    @EnvironmentObject var language: LanguageStore

    var body: some View {
        VStack(spacing: 12) {
            IsletMark(size: 84)
            Text(verbatim: AppInfo.name).font(.system(size: 28, weight: .semibold))
            Text(language.t("about.version", AppInfo.version)).foregroundStyle(.secondary)
            Text(language.t("about.madeBy", AppInfo.author)).font(.headline)
            Text(language.t("about.license")).font(.callout).foregroundStyle(.secondary)
            Link(language.t("about.github"), destination: AppInfo.repoURL)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

/// Settings window, re-titled on language change.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let model: AppModel

    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            let view = SettingsView()
                .environmentObject(model)
                .environmentObject(model.language)
                .environmentObject(model.theme)
                .environmentObject(model.accessibility)
                .environmentObject(model.weather)
                .environmentObject(model.cursor)
                .environmentObject(model.media)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.center()
            window = w
        }
        window?.title = "\(AppInfo.name) — \(model.language.t("settings.title"))"
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func retitle() {
        window?.title = "\(AppInfo.name) — \(model.language.t("settings.title"))"
    }
}
