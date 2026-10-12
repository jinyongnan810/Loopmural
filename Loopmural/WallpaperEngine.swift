import AppKit
import AVFoundation
import CoreGraphics
import Observation

/// Each display needs its own player: one AVPlayer cannot drive multiple visible layers.
@MainActor
@Observable
final class WallpaperEngine {
    /// Whether a wallpaper video is active.
    private(set) var hasWallpaper = false
    /// Whether playback was paused by the user.
    private(set) var isPaused = false
    /// Whether sleep or session inactivity prevents playback.
    private(set) var isSuspended = false
    /// Reports wallpaper playback failures.
    /// The wallpaper players and windows for connected displays.
    /// The video file used by the current wallpaper.
    /// Notification tokens and their owning centers.
    /// The active reasons for suspending playback.
    /// Identifies the latest playback request to ignore stale work.
    @ObservationIgnored var onFailure: ((String) -> Void)?
    @ObservationIgnored private var sessions: [WallpaperSession] = []
    @ObservationIgnored private var currentURL: URL?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var suspensionReasons: Set<String> = []
    @ObservationIgnored private var generation = UUID()

    /// Observes display changes, sleep, and session activity.
    init() {
        observe(NSApplication.didChangeScreenParametersNotification, center: .default) { engine in
            engine.rebuildScreens()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.screensDidSleepNotification, center: workspace) { $0.suspend("display") }
        observe(NSWorkspace.screensDidWakeNotification, center: workspace) { $0.resume("display") }
        observe(NSWorkspace.willSleepNotification, center: workspace) { $0.suspend("system") }
        observe(NSWorkspace.didWakeNotification, center: workspace) { $0.resume("system") }
        observe(NSWorkspace.sessionDidResignActiveNotification, center: workspace) { $0.suspend("session") }
        observe(NSWorkspace.sessionDidBecomeActiveNotification, center: workspace) { $0.resume("session") }
    }

    /// Validates the video and starts wallpaper playback on all displays.
    func start(url: URL, paused: Bool = false) async throws {
        let request = UUID()
        generation = request
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard playable, !tracks.isEmpty, duration.seconds.isFinite, duration.seconds > 0 else {
            throw WallpaperError.invalidVideo
        }
        try Task.checkCancellation()
        guard generation == request else { throw CancellationError() }

        closeSessions()
        currentURL = url
        isPaused = paused
        hasWallpaper = true
        rebuildScreens()
    }

    /// Updates the user’s pause preference and playback state.
    func setPaused(_ paused: Bool) {
        guard hasWallpaper else { return }
        isPaused = paused
        updatePlayback()
    }

    /// Cancels pending playback and closes all wallpaper windows.
    func stop() {
        generation = UUID()
        closeSessions()
        currentURL = nil
        hasWallpaper = false
        isPaused = false
    }

    /// Stops playback and removes all notification observers.
    func shutdown() {
        stop()
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
    }

    /// Recreates display sessions while preserving the playback position.
    private func rebuildScreens() {
        guard let url = currentURL else { return }
        let time = sessions.first?.player.currentTime() ?? .zero
        closeSessions()
        let playbackGeneration = UUID()
        generation = playbackGeneration
        sessions = NSScreen.screens.map { screen in
            WallpaperSession(url: url, screen: screen) { [weak self] message in
                guard let self, generation == playbackGeneration else { return }
                stop()
                onFailure?(message)
            }
        }
        for session in sessions {
            if time.isNumeric, time.seconds > 0 {
                session.player.seek(to: time)
            }
            session.window.orderFrontRegardless()
        }
        updatePlayback()
    }

    /// Closes and removes every display session.
    private func closeSessions() {
        for session in sessions {
            session.close()
        }
        sessions.removeAll()
    }

    /// Adds a suspension reason and pauses playback.
    private func suspend(_ reason: String) {
        suspensionReasons.insert(reason)
        isSuspended = true
        updatePlayback()
    }

    /// Clears a suspension reason and updates playback.
    private func resume(_ reason: String) {
        suspensionReasons.remove(reason)
        isSuspended = !suspensionReasons.isEmpty
        updatePlayback()
    }

    /// Plays or pauses each session based on the current state.
    private func updatePlayback() {
        for session in sessions {
            if isPaused || isSuspended {
                session.player.pause()
            } else {
                session.player.play()
            }
        }
    }

    /// Registers a notification handler on the main actor.
    private func observe(
        _ name: Notification.Name,
        center: NotificationCenter,
        action: @escaping @MainActor (WallpaperEngine) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }
}

/// Owns wallpaper playback for one display.
@MainActor
private final class WallpaperSession {
    /// The muted queue player for this display.
    let player = AVQueuePlayer()
    /// The desktop window that shows this display’s wallpaper.
    let window: DesktopWallpaperWindow
    /// Keeps the wallpaper video playing in a loop.
    private let looper: AVPlayerLooper
    /// Watches the looper for playback failures.
    private var statusObservation: NSKeyValueObservation?
    /// Watches for video items that fail during playback.
    private var failureObserver: NSObjectProtocol?

    /// Creates a looping player and desktop window for one display.
    init(url: URL, screen: NSScreen, onFailure: @escaping @MainActor (String) -> Void) {
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        window = DesktopWallpaperWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1
        )
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentView = WallpaperPlayerView(player: player)
        window.setFrame(screen.frame, display: true)

        statusObservation = looper.observe(\.status, options: [.new]) { looper, _ in
            guard looper.status == .failed else { return }
            let message = looper.error?.localizedDescription ?? String(localized: "Video playback failed.")
            Task { @MainActor in onFailure(message) }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let item = notification.object as? AVPlayerItem else { return }
            Task { @MainActor [weak self] in
                guard let self, looper.loopingPlayerItems.contains(where: { $0 === item }) else { return }
                onFailure(item.error?.localizedDescription ?? String(localized: "Video playback failed."))
            }
        }
    }

    /// Releases playback observers, player items, and the wallpaper window.
    func close() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        failureObserver = nil
        player.pause()
        looper.disableLooping()
        player.removeAllItems()
        (window.contentView as? WallpaperPlayerView)?.detachPlayer()
        window.close()
    }
}

/// Displays wallpaper without taking keyboard focus.
@MainActor
private final class DesktopWallpaperWindow: NSWindow {
    /// Prevents the wallpaper window from receiving keyboard focus.
    override var canBecomeKey: Bool { false }
    /// Prevents the wallpaper window from becoming the main window.
    override var canBecomeMain: Bool { false }
}

/// Draws the video player layer inside the wallpaper window.
@MainActor
private final class WallpaperPlayerView: NSView {
    /// The layer that renders wallpaper video frames.
    private let playerLayer = AVPlayerLayer()

    /// Creates a view backed by the supplied video player.
    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    /// Prevents creation from a storyboard or archive.
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("WallpaperPlayerView must be created with a player.")
    }

    /// Fits the video layer to the view without implicit animations.
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    /// Disconnects the video player from its rendering layer.
    func detachPlayer() {
        playerLayer.player = nil
    }
}

/// Describes video validation and library errors.
enum WallpaperError: LocalizedError {
    case invalidVideo
    case libraryUnavailable
    case missingFile

    /// The localized message for this error.
    var errorDescription: String? {
        switch self {
        case .invalidVideo:
            String(localized: "Choose a playable MP4 with a video track and a finite duration.")
        case .libraryUnavailable:
            String(localized: "The video library could not be opened. Restart Loopmural and try again.")
        case .missingFile:
            String(localized: "This library video is missing. Remove it and import the MP4 again.")
        }
    }
}
