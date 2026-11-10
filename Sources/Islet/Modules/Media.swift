import AppKit

/// Now Playing for Spotify and Apple Music.
/// • Instant updates come from the players' public distributed notifications.
/// • Artwork, position and controls use AppleScript, only for a player that is
///   already running (macOS asks once for Automation permission per player).
@MainActor
final class MediaController: ObservableObject {
    enum Player: String {
        case spotify = "Spotify"
        case music = "Music"

        var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    }

    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var player: Player
        var playing: Bool
        var duration: Double
    }

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var position: Double = 0
    @Published private(set) var volume: Double = 50
    /// Called when a different song starts.
    var onTrackChange: ((Track, NSImage?) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var poller: Timer?
    private var artworkKey = ""
    private let queue = DispatchQueue(label: "islet.applescript")

    init() {
        let center = DistributedNotificationCenter.default()
        let sources: [(String, Player)] = [
            ("com.apple.Music.playerInfo", .music),
            ("com.apple.iTunes.playerInfo", .music),
            ("com.spotify.client.PlaybackStateChanged", .spotify)
        ]
        for (name, player) in sources {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                let state = info["Player State"] as? String ?? ""
                let title = info["Name"] as? String ?? ""
                let artist = info["Artist"] as? String ?? ""
                let album = info["Album"] as? String ?? ""
                var duration = (info["Total Time"] as? Double).map { $0 / 1000 } ?? 0
                if duration == 0, let ms = info["Duration"] as? Double { duration = ms / 1000 }
                Task { @MainActor in
                    self?.apply(state: state, title: title, artist: artist, album: album,
                                duration: duration, player: player)
                }
            })
        }
        refresh()
    }

    func apply(state: String, title: String, artist: String, album: String, duration: Double, player: Player) {
        if state == "Stopped" || (title.isEmpty && artist.isEmpty) {
            if track?.player == player || track == nil {
                track = nil
                artwork = nil
                artworkKey = ""
            }
            updatePolling()
            return
        }
        let new = Track(title: title, artist: artist, album: album, player: player,
                        playing: state == "Playing", duration: duration > 0 ? duration : (track?.duration ?? 0))
        let changed = new.title != track?.title || new.artist != track?.artist
        track = new
        if changed {
            position = 0
            loadArtwork(for: new)
        }
        updatePolling()
        refresh()
    }

    // MARK: Controls

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    func seek(to seconds: Double) {
        position = seconds
        send("set player position to \(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), seconds))")
    }

    func setVolume(_ v: Double) {
        volume = v
        send("set sound volume to \(Int(v))")
    }

    private func send(_ command: String) {
        guard let player = track?.player ?? runningPlayer() else { return }
        runScript("tell application \"\(player.rawValue)\" to \(command)") { [weak self] _ in
            self?.refresh()
        }
    }

    private func runningPlayer() -> Player? {
        [Player.spotify, .music].first { $0.isRunning }
    }

    // MARK: Polling (only while something plays)

    private func updatePolling() {
        if track?.playing == true {
            guard poller == nil else { return }
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            RunLoop.main.add(t, forMode: .common)
            poller = t
        } else {
            poller?.invalidate()
            poller = nil
        }
    }

    /// Reads state, position and volume of the running player.
    func refresh() {
        guard let player = track?.player ?? runningPlayer(), player.isRunning else { return }
        let script = """
        tell application "\(player.rawValue)"
            set s to player state as string
            if s is "stopped" then return s
            set t to current track
            set d to duration of t
            return s & "||" & (name of t) & "||" & (artist of t) & "||" & (album of t) & "||" & (player position as string) & "||" & (d as string) & "||" & (sound volume as string)
        end tell
        """
        runScript(script) { [weak self] result in
            guard let self, let text = result?.stringValue else { return }
            let parts = text.components(separatedBy: "||")
            guard parts.count >= 7 else {
                if text == "stopped" { self.apply(state: "Stopped", title: "", artist: "", album: "", duration: 0, player: player) }
                return
            }
            func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
            var duration = num(parts[5])
            if player == .spotify { duration /= 1000 }
            let state = parts[0] == "playing" ? "Playing" : "Paused"
            if parts[1] != self.track?.title || state != (self.track?.playing == true ? "Playing" : "Paused") {
                self.apply(state: state, title: parts[1], artist: parts[2], album: parts[3], duration: duration, player: player)
            } else if duration > 0 {
                self.track?.duration = duration
            }
            self.position = num(parts[4])
            self.volume = num(parts[6])
        }
    }

    // MARK: Artwork

    private func loadArtwork(for track: Track) {
        let key = "\(track.player.rawValue)|\(track.title)|\(track.artist)"
        artworkKey = key
        artwork = nil
        switch track.player {
        case .spotify:
            runScript("tell application \"Spotify\" to return artwork url of current track") { [weak self] result in
                guard let s = result?.stringValue, let url = URL(string: s) else { self?.finishArtwork(nil, key: key, track: track); return }
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    let image = data.flatMap(NSImage.init(data:))
                    Task { @MainActor in self?.finishArtwork(image, key: key, track: track) }
                }.resume()
            }
        case .music:
            runScript("tell application \"Music\" to return data of artwork 1 of current track") { [weak self] result in
                let image = result.map(\.data).flatMap(NSImage.init(data:))
                self?.finishArtwork(image, key: key, track: track)
            }
        }
    }

    private func finishArtwork(_ image: NSImage?, key: String, track: Track) {
        guard key == artworkKey else { return }  // a newer track won
        artwork = image
        onTrackChange?(track, image)
    }

    // MARK: AppleScript

    private func runScript(_ source: String, completion: @escaping @MainActor (NSAppleEventDescriptor?) -> Void) {
        queue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let value = error == nil ? result : nil
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(value) } }
        }
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
