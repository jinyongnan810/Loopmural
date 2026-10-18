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
    @ObservationIgnored private var preparingSessions: [WallpaperSession] = []
    @ObservationIgnored private var currentURL: URL?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var smoothLoop = false
    @ObservationIgnored private var retiringSessions: [WallpaperSession] = []
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var suspensionReasons: Set<String> = []
    @ObservationIgnored private var generation = UUID()
    /// Whether one display player may output wallpaper audio.
    @ObservationIgnored private var allowSound = false
    /// The audio level applied to current and future display players.
    @ObservationIgnored private var volume: Float = 1

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
    func start(url: URL, paused: Bool = false, position: CMTime = .zero) async throws {
        try Task.checkCancellation()
        let request = UUID()
        generation = request
        preparingSessions.forEach { $0.close() }
        preparingSessions.removeAll()
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard playable, !tracks.isEmpty, duration.seconds.isFinite, duration.seconds > 0 else {
            throw WallpaperError.invalidVideo
        }
        try Task.checkCancellation()
        guard generation == request else { throw CancellationError() }

        // Prepare transparent windows while the current wallpaper continues playing.
        // The deferred cleanup owns these sessions until they become the active set.
        let prepared = makeSessions(url: url, duration: duration.seconds, request: request)
        preparingSessions = prepared
        var installed = false
        defer {
            if !installed { prepared.forEach { $0.close() } }
            if generation == request { preparingSessions.removeAll() }
        }
        if position.isNumeric, position.seconds > 0 {
            for session in prepared {
                try Task.checkCancellation()
                guard generation == request else { throw CancellationError() }
                await session.player.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
        // Asset validation alone does not guarantee a decoded frame. Wait for every
        // display to be ready so the fade never reveals an empty black player layer.
        let deadline = ContinuousClock.now + .seconds(10)
        while !prepared.allSatisfy(\.isReadyForDisplay) {
            try Task.checkCancellation()
            guard generation == request else { throw CancellationError() }
            guard ContinuousClock.now < deadline else { throw WallpaperError.playbackUnavailable }
            try await Task.sleep(for: .milliseconds(20))
        }
        // A stop or newer request may arrive during any suspension above.
        guard generation == request else { throw CancellationError() }
        let previous = sessions
        sessions = prepared
        installed = true
        currentURL = url
        isPaused = paused
        hasWallpaper = true
        updatePlayback()
        // Starting reveals the desktop through the incoming window. When replacing
        // a video, the outgoing window remains opaque underneath the incoming fade.
        let fadeDuration = previous.isEmpty ? 1 : 0.8
        for session in sessions {
            session.fadeIn(duration: fadeDuration)
        }
        retire(previous, duration: fadeDuration, fadeOut: false)
    }

    /// Updates the user’s pause preference and playback state.
    func setPaused(_ paused: Bool) {
        guard hasWallpaper else { return }
        isPaused = paused
        updatePlayback()
    }

    /// Applies the audio preference to current and future display sessions.
    func setSoundAllowed(_ allowed: Bool) {
        allowSound = allowed
        updatePlayback()
    }

    /// Updates audio levels without interrupting playback.
    func setVolume(_ value: Double) {
        volume = Float(min(max(value, 0), 1))
        updatePlayback()
    }

    /// Cancels pending playback and fades active wallpaper windows back to the desktop.
    func stop() {
        rebuildTask?.cancel()
        rebuildTask = nil
        generation = UUID()
        preparingSessions.forEach { $0.close() }
        preparingSessions.removeAll()
        // Remove older transitions first so stopping cannot reveal a previous video.
        retiringSessions.forEach { $0.close() }
        retiringSessions.removeAll()
        retire(sessions, duration: 0.7, fadeOut: true)
        sessions.removeAll()
        currentURL = nil
        hasWallpaper = false
        isPaused = false
    }

    /// Stops playback and removes all notification observers.
    func shutdown() {
        stop()
        retiringSessions.forEach { $0.close() }
        retiringSessions.removeAll()
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
    }

    /// Recreates display sessions while preserving the playback position.
    private func rebuildScreens() {
        guard let url = currentURL else { return }
        let time = sessions.first?.player.currentTime() ?? .zero
        let paused = isPaused
        rebuildTask?.cancel()
        // A disconnected display has no image to preserve during the fade. Release
        // its decoders now, even if preparing the remaining displays later fails.
        let displayIDs = Set(NSScreen.screens.map { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber })
        sessions.removeAll { session in
            guard !displayIDs.contains(session.displayID) else { return false }
            session.close()
            return true
        }
        retiringSessions.removeAll { session in
            guard !displayIDs.contains(session.displayID) else { return false }
            session.close()
            return true
        }
        preparingSessions.forEach { $0.close() }
        preparingSessions.removeAll()
        rebuildTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await start(url: url, paused: paused, position: time)
            } catch is CancellationError {
                // A newer selection, stop, or screen change superseded this rebuild.
            } catch {
                onFailure?(error.localizedDescription)
            }
        }
    }

    /// Creates one independently rendered session per display, honoring Reduce Motion.
    private func makeSessions(url: URL, duration: Double, request: UUID) -> [WallpaperSession] {
        NSScreen.screens.map { screen in
            WallpaperSession(url: url, duration: duration, smoothLoop: smoothLoop && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, screen: screen) { [weak self] message in
                guard let self, generation == request else { return }
                stop()
                onFailure?(message)
            }
        }
    }

    /// Applies the optional loop blend to future and current playback sessions.
    func setSmoothLoop(_ enabled: Bool) {
        guard smoothLoop != enabled else { return }
        smoothLoop = enabled
        rebuildScreens()
    }

    /// Keeps the old image underneath the incoming video until its fade completes.
    private func retire(_ old: [WallpaperSession], duration: Double, fadeOut: Bool) {
        retiringSessions.append(contentsOf: old)
        for session in old {
            session.setPlayback(paused: fadeOut || isPaused || isSuspended, muted: true, volume: volume)
            if fadeOut { session.fadeOut(duration: duration) }
        }
        // Retain outgoing windows until the visual transition finishes. close() is
        // idempotent because stop or shutdown may already have released them.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            old.forEach { $0.close() }
            self?.retiringSessions.removeAll { item in old.contains { $0 === item } }
        }
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
        for session in retiringSessions {
            session.setPlayback(paused: !hasWallpaper || isPaused || isSuspended, muted: true, volume: volume)
        }
        for (index, session) in sessions.enumerated() {
            // Output audio once even when the wallpaper spans multiple displays.
            session.setPlayback(paused: isPaused || isSuspended, muted: !allowSound || index != 0, volume: volume)
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

/// Owns wallpaper playback and optional overlapping loop players for one display.
@MainActor
private final class WallpaperSession {
    let window: DesktopWallpaperWindow
    let displayID: NSNumber?
    private let players: [AVPlayer]
    private let videoView: WallpaperPlayerView
    private var looper: AVPlayerLooper?
    private var observations: [NSKeyValueObservation] = []
    private var loopTask: Task<Void, Never>?
    private var failureObserver: NSObjectProtocol?
    // Smooth looping alternates roles: one player shows the ending while the other
    // starts at zero. After the blend, the old player rewinds offscreen for reuse.
    private var activeIndex = 0
    private var blendStarted = false
    /// Prevents reuse of the hidden player until its rewind has completed.
    private var standbyReady = true
    private var paused = true
    private var volume: Float = 1
    private var closed = false
    private let duration: Double
    private let overlap: Double

    /// The visible player, also used to preserve position when rebuilding displays.
    var player: AVPlayer { players[activeIndex] }
    /// Indicates that the visible layer has a decoded first frame.
    var isReadyForDisplay: Bool { videoView.isReady(at: activeIndex) }

    init(url: URL, duration: Double, smoothLoop: Bool, screen: NSScreen, onFailure: @escaping @MainActor (String) -> Void) {
        self.duration = duration
        displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        // Bound the overlap for short clips so most of each cycle remains unblended.
        overlap = min(0.5, duration / 4)
        // Ordinary loops use AVPlayerLooper. Smooth loops need two ordinary players
        // that hold their final frame instead of automatically advancing or rewinding.
        players = (0 ..< (smoothLoop ? 2 : 1)).map { _ in
            let player: AVPlayer = smoothLoop
                ? AVPlayer(playerItem: AVPlayerItem(url: url))
                : AVQueuePlayer()
            player.isMuted = true
            if smoothLoop { player.actionAtItemEnd = .pause }
            return player
        }
        if let queue = players[0] as? AVQueuePlayer {
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        }
        videoView = WallpaperPlayerView(players: players)
        window = DesktopWallpaperWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentView = videoView
        window.setFrame(screen.frame, display: true)
        window.alphaValue = 0
        window.orderFrontRegardless()
        for player in players {
            if let item = player.currentItem {
                observations.append(item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    guard item.status == .failed else { return }
                    let message = item.error?.localizedDescription ?? String(localized: "Video playback failed.")
                    Task { @MainActor [weak self] in
                        guard let self, !closed else { return }
                        onFailure(message)
                    }
                })
            }
        }
        if let looper {
            observations.append(looper.observe(\.status, options: [.new]) { [weak self] looper, _ in
                guard looper.status == .failed else { return }
                let message = looper.error?.localizedDescription ?? String(localized: "Video playback failed.")
                Task { @MainActor [weak self] in
                    guard let self, !closed else { return }
                    onFailure(message)
                }
            })
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let item = notification.object as? AVPlayerItem else { return }
            Task { @MainActor [weak self] in
                guard let self, !closed,
                      players.contains(where: { $0.currentItem === item }) ||
                      looper?.loopingPlayerItems.contains(where: { $0 === item }) == true else { return }
                onFailure(item.error?.localizedDescription ?? String(localized: "Video playback failed."))
            }
        }
    }

    /// Applies transport and sound settings to both sides of any in-progress blend.
    func setPlayback(paused: Bool, muted: Bool, volume: Float) {
        guard !closed else { return }
        self.paused = paused
        self.volume = volume
        for (index, player) in players.enumerated() {
            player.isMuted = muted
            if paused || (index != activeIndex && !blendStarted) { player.pause() } else { player.play() }
        }
        // Stop periodic work entirely while paused or asleep; media time preserves
        // the blend position so resuming continues from the same visual state.
        if paused {
            loopTask?.cancel()
            loopTask = nil
        } else if players.count == 2, loopTask == nil {
            loopTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.updateLoop()
                    do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                }
            }
        }
        updateGains(progress: blendStarted ? min(players[1 - activeIndex].currentTime().seconds / overlap, 1) : 0)
    }

    /// Uses playback time so pausing or sleeping also pauses a loop blend.
    private func updateLoop() {
        guard !closed, !paused, players.count == 2 else { return }
        let next = 1 - activeIndex
        if !blendStarted {
            guard standbyReady, player.currentTime().seconds >= duration - overlap,
                  videoView.isReady(at: next) else { return }
            blendStarted = true
            videoView.prepareBlend(from: activeIndex, to: next)
            players[next].play()
        }
        // Drive opacity from the incoming player, not wall-clock time. If decoding
        // stalls, the fade waits for actual playback rather than racing ahead.
        let progress = min(max(players[next].currentTime().seconds / overlap, 0), 1)
        videoView.setBlend(progress: Float(progress), incoming: next)
        updateGains(progress: progress)
        // The incoming player has already consumed the overlap. Continue from there,
        // shortening the effective loop by that overlap rather than replaying it.
        if progress >= 1 {
            let previous = activeIndex
            activeIndex = next
            blendStarted = false
            standbyReady = false
            players[previous].pause()
            videoView.finishBlend(active: activeIndex)
            players[previous].seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                Task { @MainActor [weak self] in
                    guard let self, !closed else { return }
                    standbyReady = finished
                }
            }
            updateGains(progress: 0)
        }
    }

    /// Crossfades loop audio using complementary gains at the user’s chosen volume.
    private func updateGains(progress: Double) {
        for (index, player) in players.enumerated() {
            let gain = index == activeIndex ? 1 - progress : progress
            player.volume = volume * Float(gain)
        }
    }

    /// Reveals this window over the desktop or an outgoing wallpaper window.
    func fadeIn(duration: Double) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : duration
            window.animator().alphaValue = 1
        }
    }

    /// Reveals the desktop before the engine releases the window.
    func fadeOut(duration: Double) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : duration
            window.animator().alphaValue = 0
        }
    }

    /// Releases observers, looping work, decoders, and windows exactly once.
    func close() {
        guard !closed else { return }
        closed = true
        loopTask?.cancel()
        loopTask = nil
        observations.removeAll()
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
        looper?.disableLooping()
        looper = nil
        for player in players {
            player.pause()
            if let queue = player as? AVQueuePlayer {
                queue.items().forEach { $0.cancelPendingSeeks() }
                queue.removeAllItems()
            } else {
                player.currentItem?.cancelPendingSeeks()
                player.replaceCurrentItem(with: nil)
            }
        }
        videoView.detachPlayer()
        window.contentView = nil
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
    /// One layer per player; only the incoming layer changes opacity during a blend.
    private let playerLayers: [AVPlayerLayer]

    /// Creates a view backed by the supplied video player.
    init(players: [AVPlayer]) {
        playerLayers = players.map { AVPlayerLayer(player: $0) }
        super.init(frame: .zero)
        wantsLayer = true
        for (index, playerLayer) in playerLayers.enumerated() {
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.opacity = index == 0 ? 1 : 0
            layer?.addSublayer(playerLayer)
        }
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
        for playerLayer in playerLayers {
            playerLayer.frame = bounds
        }
        CATransaction.commit()
    }

    /// Checks decoded-frame readiness rather than just asset or item readiness.
    func isReady(at index: Int) -> Bool { playerLayers[index].isReadyForDisplay }

    /// Places the transparent incoming layer above the fully opaque outgoing layer.
    func prepareBlend(from: Int, to: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayers[from].opacity = 1
        playerLayers[to].opacity = 0
        layer?.addSublayer(playerLayers[to])
        CATransaction.commit()
    }

    /// Applies media-driven opacity immediately, without a second implicit animation.
    func setBlend(progress: Float, incoming: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayers[incoming].opacity = progress
        CATransaction.commit()
    }

    /// Hides the outgoing layer before its player rewinds for the next loop.
    func finishBlend(active: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, layer) in playerLayers.enumerated() {
            layer.opacity = index == active ? 1 : 0
        }
        CATransaction.commit()
    }

    /// Disconnects the video player from its rendering layer.
    func detachPlayer() {
        for playerLayer in playerLayers {
            playerLayer.player = nil
        }
    }
}

/// Describes video validation and library errors.
enum WallpaperError: LocalizedError {
    case invalidVideo
    case libraryUnavailable
    case missingFile
    /// A valid video did not produce a displayable frame before preparation timed out.
    case playbackUnavailable

    /// The localized message for this error.
    var errorDescription: String? {
        switch self {
        case .invalidVideo:
            String(localized: "Choose a playable MP4 or MOV with a video track and a finite duration.")
        case .libraryUnavailable:
            String(localized: "The video library could not be opened. Restart Loopmural and try again.")
        case .playbackUnavailable:
            String(localized: "Video playback could not start. Try selecting the video again.")
        case .missingFile:
            String(localized: "This library video is missing. Remove it and import the video again.")
        }
    }
}
