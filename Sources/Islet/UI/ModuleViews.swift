import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: Shared styling

/// Inner card on the island body.
struct IslandCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var a11y: AccessibilityState

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.tokens.card.color.opacity(a11y.reduceTransparency ? 1 : 0.92)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(a11y.increaseContrast ? 0.35 : 0.06), lineWidth: 1))
    }
}

/// Icon button used across the island (hover highlight, focus ring, press).
struct IslandIconButton: View {
    var symbol: String
    var label: String
    var size: CGFloat = 28
    var selected = false
    var prominent = false
    var action: () -> Void
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var a11y: AccessibilityState
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(prominent ? Color.black : (selected ? Color.white : Color.white.opacity(hover ? 0.95 : 0.6)))
                .background(Circle().fill(prominent ? Color.white : Color.white.opacity(selected ? 0.18 : (hover ? 0.1 : 0))))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .help(label)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration)
    }
}

private struct PressableBody: View {
    let configuration: ButtonStyleConfiguration
    @EnvironmentObject var a11y: AccessibilityState
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !a11y.reduceMotion ? 0.9 : 1)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white, lineWidth: 2).padding(-2).opacity(focused ? 1 : 0))
            .animation(a11y.spring(0.25, damping: 0.6), value: configuration.isPressed)
    }
}

// MARK: Expanded

struct ExpandedView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var interaction: IslandInteraction
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var a11y: AccessibilityState

    private let leftTabs: [IslandModule] = [.home, .clipboard, .shelf]
    private let rightTabs: [IslandModule] = [.notes, .weather, .command]

    var body: some View {
        VStack(spacing: 8) {
            // Header lives in the black band next to the camera housing.
            HStack(spacing: 4) {
                ForEach(leftTabs) { tab($0) }
                Spacer(minLength: model.notchSize.width + 8)
                ForEach(rightTabs) { tab($0) }
                IslandIconButton(symbol: "gearshape", label: language.t("menu.settings"), size: 26) {
                    AppDelegate.shared?.openSettings()
                }
                IslandIconButton(symbol: "chevron.up", label: language.t("a11y.collapse"), size: 26) {
                    interaction.collapse()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22)
            .frame(height: model.bandHeight)

            Group {
                switch model.selectedModule {
                case .home: HomeTab()
                case .clipboard: ClipboardTab()
                case .shelf: ShelfTab()
                case .notes: NotesTab()
                case .weather: WeatherTab()
                case .command: CommandTab()
                }
            }
            .id(model.selectedModule)
            .transition(.opacity.combined(with: .offset(y: 6)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .foregroundStyle(theme.tokens.islandPrimary.color)
        .animation(a11y.spring(0.35, damping: 0.86), value: model.selectedModule)
    }

    private func tab(_ m: IslandModule) -> some View {
        IslandIconButton(symbol: m.symbol, label: language.t(m.titleKey), size: 26,
                         selected: model.selectedModule == m) {
            model.selectedModule = m
            interaction.clickedInside()
        }
    }
}

// MARK: Home

struct HomeTab: View {
    @EnvironmentObject var language: LanguageStore

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                MediaCard().frame(width: 316)
                QuickActionsGrid().frame(maxWidth: .infinity)
            }
            .frame(height: 162)
            DockRow().frame(height: 46)
        }
    }
}

struct MediaCard: View {
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var theme: ThemeStore
    @State private var scrub: Double?

    var body: some View {
        IslandCard {
            if let track = media.track {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        ArtworkView(image: media.artwork, size: 58, radius: 12)
                            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: track.player == .spotify ? "SPOTIFY" : "MUSIC")
                                .font(.system(size: 9, weight: .bold)).tracking(0.8)
                                .foregroundStyle(theme.tokens.islandSecondary.color)
                            Text(verbatim: isolated(track.title)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Text(verbatim: isolated(track.artist)).font(.system(size: 12))
                                .foregroundStyle(theme.tokens.islandSecondary.color).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        AudioBars(playing: track.playing, color: theme.tokens.islandPrimary.color)
                            .frame(width: 22, height: 14)
                    }
                    Scrubber(value: scrub ?? media.position, total: max(track.duration, 1)) { v, done in
                        scrub = done ? nil : v
                        if done { media.seek(to: v) }
                    }
                    HStack {
                        Text(verbatim: MediaController.format(scrub ?? media.position))
                        Spacer()
                        Text(verbatim: "-" + MediaController.format(max(0, track.duration - (scrub ?? media.position))))
                    }
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.tokens.islandSecondary.color)
                    HStack(spacing: 14) {
                        Image(systemName: "speaker.wave.1.fill").font(.system(size: 9))
                            .foregroundStyle(theme.tokens.islandSecondary.color)
                        Scrubber(value: media.volume, total: 100) { v, done in if done { media.setVolume(v) } }
                            .frame(width: 70)
                        Spacer()
                        IslandIconButton(symbol: "backward.fill", label: language.t("media.previous"), size: 28) { media.previous() }
                        IslandIconButton(symbol: track.playing ? "pause.fill" : "play.fill",
                                         label: language.t(track.playing ? "media.pause" : "media.play"),
                                         size: 34, prominent: true) { media.playPause() }
                        IslandIconButton(symbol: "forward.fill", label: language.t("media.next"), size: 28) { media.next() }
                        Spacer()
                    }
                }
            } else {
                EmptyStateView(symbol: "music.note", title: language.t("media.nothing"), detail: language.t("media.hint"))
            }
        }
    }
}

/// Thin draggable bar for progress and volume.
struct Scrubber: View {
    var value: Double
    var total: Double
    var onChange: (Double, Bool) -> Void
    @EnvironmentObject var theme: ThemeStore
    @State private var hover = false

    var body: some View {
        GeometryReader { geo in
            let f = total > 0 ? min(max(value / total, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(theme.tokens.islandPrimary.color.opacity(0.18))
                Capsule().fill(theme.tokens.islandPrimary.color).frame(width: max(3, geo.size.width * f))
            }
            .frame(height: hover ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in onChange(Double(min(max(g.location.x / geo.size.width, 0), 1)) * total, false) }
                .onEnded { g in onChange(Double(min(max(g.location.x / geo.size.width, 0), 1)) * total, true) })
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int(total > 0 ? value / total * 100 : 0))%"))
        .accessibilityAdjustableAction { dir in
            let step = total / 20
            onChange(dir == .increment ? min(total, value + step) : max(0, value - step), true)
        }
    }
}

struct QuickActionsGrid: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var language: LanguageStore

    var body: some View {
        let actions: [(String, String, () -> Void)] = [
            ("camera.viewfinder", language.t("action.screenshot"), QuickActions.screenshot),
            ("eyedropper", language.t("action.picker"), { QuickActions.pickColor(model) }),
            ("keyboard", language.t("action.layout"), { QuickActions.transformClipboard(model, TextTools.fixLayout) }),
            ("character.cursor.ibeam", language.t("action.translit"), { QuickActions.transformClipboard(model, TextTools.transliterate) }),
            ("textformat.size.larger", language.t("action.upper"), { QuickActions.transformClipboard(model) { $0.uppercased() } }),
            ("timer", language.t("action.timer5"), {
                model.timer.setMinutes(5); model.timer.start(); model.interaction.collapse()
            })
        ]
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(actions.indices, id: \.self) { i in
                QuickActionTile(symbol: actions[i].0, title: actions[i].1, action: actions[i].2)
            }
        }
    }
}

struct QuickActionTile: View {
    var symbol: String
    var title: String
    var action: () -> Void
    @EnvironmentObject var theme: ThemeStore
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).frame(width: 18)
                Text(title).font(.system(size: 11.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.tokens.card.color.opacity(hover ? 1 : 0.85)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(hover ? 0.14 : 0.05), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .help(title)
    }
}

@MainActor
enum QuickActions {
    static func screenshot() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func pickColor(_ model: AppModel) {
        model.interaction.collapse()
        NSColorSampler().show { color in
            guard let c = color?.usingColorSpace(.sRGB) else { return }
            let hex = RGB(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent)).hexString
            MainActor.assumeIsolated {
                model.clipboard.write(hex)
                model.toast(IslandActivity(symbol: "eyedropper.full", title: hex,
                                           subtitle: model.language.t("toast.inClipboard"),
                                           tint: Color(nsColor: c)), force: true)
            }
        }
    }

    static func transformClipboard(_ model: AppModel, _ f: (String) -> String) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            model.interaction.collapse()
            model.toast(IslandActivity(symbol: "doc.on.clipboard", title: model.language.t("toast.emptyClipboard"),
                                       subtitle: model.language.t("toast.copyFirst")), force: true)
            return
        }
        let out = f(text)
        model.clipboard.write(out)
        model.interaction.collapse()
        model.toast(IslandActivity(symbol: "checkmark.circle.fill", title: model.language.t("toast.done"),
                                   subtitle: out.replacingOccurrences(of: "\n", with: " "), tint: .green), force: true)
    }
}

struct DockRow: View {
    @EnvironmentObject var dock: AppDock
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var interaction: IslandInteraction

    var body: some View {
        IslandCard(padding: 6) {
            HStack(spacing: 6) {
                ForEach(dock.apps, id: \.id) { app in
                    DockIcon(url: app.url) {
                        dock.launch(app.url)
                        interaction.collapse()
                    }
                    .contextMenu {
                        Button(language.t("dock.remove")) { dock.remove(app.id) }
                    }
                }
                IslandIconButton(symbol: "plus", label: language.t("dock.add"), size: 28) {
                    let panel = NSOpenPanel()
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.allowedContentTypes = [.application]
                    panel.allowsMultipleSelection = true
                    NSApp.activate(ignoringOtherApps: true)
                    if panel.runModal() == .OK { panel.urls.forEach(dock.add) }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct DockIcon: View {
    let url: URL
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 30, height: 30)
                .scaleEffect(hover ? 1.15 : 1, anchor: .bottom)
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { hover = h } }
        .help(FileManager.default.displayName(atPath: url.path))
        .accessibilityLabel(Text(FileManager.default.displayName(atPath: url.path)))
    }
}

// MARK: Clipboard

struct ClipboardTab: View {
    @EnvironmentObject var clipboard: ClipboardHistory
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                SearchField(text: $clipboard.query, placeholder: language.t("clipboard.search"))
                IslandIconButton(symbol: "trash", label: language.t("clipboard.clear"), size: 28) { clipboard.clearUnpinned() }
            }
            if clipboard.filtered.isEmpty {
                IslandCard { EmptyStateView(symbol: "doc.on.clipboard", title: language.t("clipboard.empty"), detail: language.t("clipboard.hint")) }
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(clipboard.filtered) { item in
                            ClipboardRow(item: item)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }
}

private struct ClipboardRow: View {
    let item: ClipboardHistory.Item
    @EnvironmentObject var clipboard: ClipboardHistory
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var model: AppModel
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isLink ? "link" : "text.alignleft")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.text.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 12)).lineLimit(1)
                HStack(spacing: 4) {
                    if item.pinned { Image(systemName: "pin.fill").font(.system(size: 8)) }
                    Text(verbatim: [item.sourceApp, item.date.formatted(.relative(presentation: .named).locale(language.locale))]
                        .compactMap { $0 }.joined(separator: " · "))
                }
                .font(.system(size: 10)).foregroundStyle(theme.tokens.islandSecondary.color)
            }
            Spacer(minLength: 4)
            if hover {
                IslandIconButton(symbol: item.pinned ? "pin.slash" : "pin", label: language.t("clipboard.pin"), size: 24) { clipboard.togglePin(item) }
                IslandIconButton(symbol: "xmark", label: language.t("clipboard.delete"), size: 24) { clipboard.delete(item) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(hover ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hover = h } }
        .onTapGesture {
            clipboard.copy(item)
            model.interaction.collapse()
            model.toast(IslandActivity(symbol: "doc.on.clipboard.fill", title: language.t("toast.copied"),
                                       subtitle: language.t("toast.pasteHint")), force: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    var autofocus = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).opacity(0.6)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(focused ? 0.4 : 0.06)))
        .onAppear { if autofocus { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true } } }
    }
}

// MARK: Shelf

struct ShelfTab: View {
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var shelf: ShelfModel
    @EnvironmentObject var model: AppModel

    var body: some View {
        IslandCard {
            if shelf.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 28, weight: .light))
                    Text(language.t("shelf.empty")).font(.system(size: 14, weight: .semibold))
                    Text(language.t("shelf.hint")).font(.system(size: 11))
                        .foregroundStyle(theme.tokens.islandSecondary.color).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                    .foregroundStyle(Color.white.opacity(model.dropTargeted ? 0.8 : 0.2)))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(language.plural("shelf.count", shelf.items.count)).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button(language.t("shelf.clear")) { withAnimation { shelf.clear() } }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).opacity(0.7)
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(shelf.items, id: \.self) { ShelfItemView(url: $0) }
                        }
                    }
                    .scrollIndicators(.never)
                    Text(language.t("shelf.dragOut")).font(.system(size: 10.5))
                        .foregroundStyle(theme.tokens.islandSecondary.color)
                }
            }
        }
    }
}

private struct ShelfItemView: View {
    let url: URL
    @EnvironmentObject var shelf: ShelfModel
    @EnvironmentObject var language: LanguageStore
    @State private var hover = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 52, height: 52)
                .scaleEffect(hover ? 1.06 : 1)
            Text(verbatim: isolated(url.lastPathComponent))
                .font(.system(size: 10.5)).lineLimit(2).multilineTextAlignment(.center).frame(width: 84)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(hover ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { hover = h } }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button(language.t("shelf.open")) { NSWorkspace.shared.open(url) }
            Button(language.t("shelf.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button(language.t("shelf.remove")) { withAnimation { shelf.remove(url) } }
        }
        .help(url.path)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(language.t("shelf.remove"))) { shelf.remove(url) }
    }
}

// MARK: Notes + Timer

struct NotesTab: View {
    @EnvironmentObject var notes: NotesModel
    @EnvironmentObject var timer: TimerModel
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        HStack(spacing: 10) {
            IslandCard(padding: 8) {
                ZStack(alignment: .topLeading) {
                    if notes.text.isEmpty {
                        Text(language.t("notes.placeholder")).font(.system(size: 13))
                            .foregroundStyle(theme.tokens.islandSecondary.color).padding(.top, 1).padding(.leading, 5)
                    }
                    TextEditor(text: $notes.text)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                }
            }
            IslandCard {
                VStack(spacing: 10) {
                    ZStack {
                        ProgressRing(progress: timer.isActive || timer.finished ? 1 - timer.progress : 1, color: .orange, lineWidth: 5)
                        Text(verbatim: TimerModel.format(timer.remaining))
                            .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    }
                    .frame(width: 92, height: 92)
                    .animation(.linear(duration: 0.25), value: timer.remaining)
                    HStack(spacing: 4) {
                        ForEach([5, 10, 15, 25, 45], id: \.self) { m in
                            Button { timer.setMinutes(m) } label: {
                                Text(verbatim: "\(m)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .frame(width: 26, height: 22)
                                    .background(Capsule().fill(Color.white.opacity(Int(timer.total) == m * 60 ? 0.22 : 0.08)))
                            }
                            .buttonStyle(PressableStyle())
                            .disabled(timer.running)
                            .help(language.t("timer.minutes", m))
                        }
                    }
                    HStack(spacing: 8) {
                        Button { timer.running ? timer.pause() : timer.start() } label: {
                            Label(language.t(timer.running ? "timer.pause" : "timer.start"),
                                  systemImage: timer.running ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12).frame(height: 28)
                                .background(Capsule().fill(Color.orange))
                        }
                        .buttonStyle(PressableStyle())
                        IslandIconButton(symbol: "arrow.counterclockwise", label: language.t("timer.reset"), size: 28) { timer.reset() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 210)
        }
    }
}

// MARK: Weather

struct WeatherTab: View {
    @EnvironmentObject var weather: WeatherService
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        if let temp = weather.temperature {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(weather.resolvedCity ?? weather.city, systemImage: "location.fill")
                        .font(.system(size: 12, weight: .semibold))
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 30))
                        Text(verbatim: "\(Int(temp.rounded()))°").font(.system(size: 40, weight: .light).monospacedDigit())
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        if let w = weather.wind { Label(String(format: "%.0f km/h", w), systemImage: "wind") }
                        if let h = weather.humidity { Label("\(Int(h))%", systemImage: "humidity") }
                    }
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
                }
                .padding(14)
                .frame(width: 190, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(
                    LinearGradient(colors: [Color(red: 0.25, green: 0.48, blue: 0.85), Color(red: 0.55, green: 0.62, blue: 0.68)],
                                   startPoint: .top, endPoint: .bottom)))

                VStack(spacing: 8) {
                    IslandCard(padding: 8) {
                        HStack(spacing: 0) {
                            ForEach(weather.hours) { h in
                                VStack(spacing: 4) {
                                    Text(verbatim: h.date.formatted(.dateTime.hour().locale(language.locale)))
                                        .font(.system(size: 9.5)).foregroundStyle(theme.tokens.islandSecondary.color)
                                    Image(systemName: WeatherService.symbol(h.code)).symbolRenderingMode(.multicolor).font(.system(size: 13))
                                    Text(verbatim: "\(Int(h.temp.rounded()))°").font(.system(size: 11, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(height: 70)
                    IslandCard(padding: 8) {
                        let lo = weather.days.map(\.min).min() ?? 0, hi = weather.days.map(\.max).max() ?? 1
                        VStack(spacing: 2) {
                            ForEach(weather.days.prefix(5)) { d in
                                HStack(spacing: 8) {
                                    Text(verbatim: d.date.formatted(.dateTime.weekday(.abbreviated).locale(language.locale)))
                                        .font(.system(size: 11)).frame(width: 34, alignment: .leading)
                                    Image(systemName: WeatherService.symbol(d.code)).symbolRenderingMode(.multicolor)
                                        .font(.system(size: 11)).frame(width: 18)
                                    Text(verbatim: "\(Int(d.min.rounded()))°").font(.system(size: 10.5).monospacedDigit())
                                        .foregroundStyle(theme.tokens.islandSecondary.color).frame(width: 28, alignment: .trailing)
                                    GeometryReader { g in
                                        let span = max(hi - lo, 1)
                                        Capsule().fill(Color.white.opacity(0.12))
                                            .overlay(alignment: .leading) {
                                                Capsule().fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                                                    .frame(width: max(6, g.size.width * (d.max - d.min) / span))
                                                    .offset(x: g.size.width * (d.min - lo) / span)
                                            }
                                    }
                                    .frame(height: 4)
                                    Text(verbatim: "\(Int(d.max.rounded()))°").font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                        .frame(width: 28, alignment: .trailing)
                                }
                                .frame(maxHeight: .infinity)
                            }
                        }
                    }
                }
            }
        } else {
            IslandCard {
                EmptyStateView(symbol: weather.enabled ? "cloud.sun" : "cloud.slash",
                               title: language.t(weather.failed ? "weather.failed" : (weather.enabled ? "weather.loading" : "weather.off")),
                               detail: language.t("weather.hint"))
            }
        }
    }
}

// MARK: Command bar (⌥Space)

struct CommandTab: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let results = CommandEngine.results(for: model.commandQuery, model: model)
        VStack(spacing: 8) {
            SearchField(text: $model.commandQuery, placeholder: language.t("command.placeholder"),
                        onSubmit: { results.first?.run() }, autofocus: true)
            IslandCard(padding: 6) {
                if results.isEmpty {
                    EmptyStateView(symbol: "command", title: language.t("command.title"), detail: language.t("command.hint"))
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(results.prefix(7).enumerated()), id: \.offset) { i, r in
                                CommandRow(result: r, primary: i == 0)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }
}

struct CommandResult {
    var symbol: String
    var icon: NSImage?
    var title: String
    var detail: String
    var run: () -> Void
}

private struct CommandRow: View {
    let result: CommandResult
    let primary: Bool
    @EnvironmentObject var theme: ThemeStore
    @State private var hover = false

    var body: some View {
        Button(action: result.run) {
            HStack(spacing: 10) {
                Group {
                    if let icon = result.icon { Image(nsImage: icon).resizable() } else {
                        Image(systemName: result.symbol).font(.system(size: 12, weight: .semibold))
                    }
                }
                .frame(width: 22, height: 22)
                Text(result.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                Text(result.detail).font(.system(size: 10.5)).foregroundStyle(theme.tokens.islandSecondary.color).lineLimit(1)
                if primary { Image(systemName: "return").font(.system(size: 10)).opacity(0.6) }
            }
            .padding(.horizontal, 8).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(primary || hover ? 0.09 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

@MainActor
enum CommandEngine {
    private static var appCache: [URL] = {
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"]
        return dirs.flatMap { dir in
            ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
                .filter { $0.hasSuffix(".app") }
                .map { URL(fileURLWithPath: dir).appendingPathComponent($0) }
        }
    }()

    static func results(for raw: String, model: AppModel) -> [CommandResult] {
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let l = model.language
        var out: [CommandResult] = []

        if let v = Calculator.evaluate(q) {
            let text = v.rounded() == v && abs(v) < 1e15 ? String(Int64(v)) : v.formatted(.number.precision(.fractionLength(0...6)).locale(l.locale))
            out.append(CommandResult(symbol: "equal", title: "= " + text, detail: l.t("command.copyResult")) {
                model.clipboard.write(text)
                model.interaction.collapse()
                model.toast(IslandActivity(symbol: "equal.circle.fill", title: text, subtitle: l.t("toast.inClipboard")), force: true)
            })
        }

        let lower = q.lowercased()
        for prefix in ["timer ", "таймер "] where lower.hasPrefix(prefix) {
            if let m = Int(lower.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces).prefix(while: \.isNumber)), m > 0 {
                out.append(CommandResult(symbol: "timer", title: l.t("command.timer", m), detail: "Islet") {
                    model.timer.setMinutes(m); model.timer.start()
                    model.interaction.collapse()
                })
            }
        }

        let apps = appCache.filter { $0.deletingPathExtension().lastPathComponent.lowercased().contains(lower) }
            .sorted { a, b in
                let x = a.deletingPathExtension().lastPathComponent.lowercased().hasPrefix(lower)
                let y = b.deletingPathExtension().lastPathComponent.lowercased().hasPrefix(lower)
                return x != y ? x : a.lastPathComponent < b.lastPathComponent
            }
        for app in apps.prefix(4) {
            out.append(CommandResult(symbol: "app", icon: NSWorkspace.shared.icon(forFile: app.path),
                                     title: FileManager.default.displayName(atPath: app.path), detail: l.t("command.open")) {
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                model.interaction.collapse()
            })
        }

        out.append(CommandResult(symbol: "globe", title: l.t("command.web", q), detail: l.t("command.browser")) {
            var c = URLComponents(string: "https://duckduckgo.com/")!
            c.queryItems = [URLQueryItem(name: "q", value: q)]
            if let url = c.url { NSWorkspace.shared.open(url) }
            model.interaction.collapse()
        })
        return out
    }
}

// MARK: Empty state

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var detail: String?
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light)).accessibilityHidden(true)
            Text(title).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(.system(size: 11))
                    .foregroundStyle(theme.tokens.islandSecondary.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
