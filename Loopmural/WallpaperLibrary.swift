import AppKit
import AVFoundation
import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

/// Manages imported videos, saved preferences, and wallpaper playback.
@MainActor
@Observable
final class WallpaperLibrary {
    /// The shared instance used throughout the app.
    static let shared = WallpaperLibrary()

    /// Imported videos ordered from newest to oldest.
    private(set) var videos: [WallpaperVideo] = []
    /// Pinned videos ordered from newest to oldest.
    private(set) var pinnedVideos: [WallpaperVideo] = []
    /// Unpinned videos ordered from newest to oldest.
    private(set) var unpinnedVideos: [WallpaperVideo] = []
    /// The identifier of the selected wallpaper video.
    private(set) var selectedID: UUID?
    /// Whether video imports are in progress.
    private(set) var isImporting = false
    /// Whether a wallpaper change is in progress.
    private(set) var isApplying = false
    /// Cached preview images keyed by video identifier.
    private(set) var thumbnails: [UUID: NSImage] = [:]
    /// The latest error to show to the user.
    var errorMessage: String?
    /// The video awaiting removal confirmation.
    var pendingRemoval: WallpaperVideo?
    /// The video awaiting a new title.
    var pendingRename: WallpaperVideo?
    /// Plays wallpaper videos across connected displays.
    let engine = WallpaperEngine()
    /// Whether to restore the last wallpaper when the app opens.
    var restoreOnLaunch: Bool {
        didSet { UserDefaults.standard.set(restoreOnLaunch, forKey: "restoreOnLaunch") }
    }

    /// Whether the end and beginning of a video overlap when looping.
    var smoothLoop: Bool {
        didSet {
            defaults.set(smoothLoop, forKey: "smoothLoop")
            engine.setSmoothLoop(smoothLoop)
        }
    }

    /// Whether wallpaper videos can play audio.
    var allowSound: Bool {
        didSet {
            defaults.set(allowSound, forKey: "allowSound")
            engine.setSoundAllowed(allowSound)
        }
    }

    /// The saved wallpaper audio level, from silent to full volume.
    var volume: Double {
        didSet {
            defaults.set(volume, forKey: "volume")
            engine.setVolume(volume)
        }
    }

    /// The SwiftData store for video metadata.
    /// The folder containing app-owned video copies.
    /// The active file picker, if one is open.
    /// Stores wallpaper selection and playback preferences.
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private var importPanel: NSOpenPanel?
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// The library video matching the selected identifier.
    var selectedVideo: WallpaperVideo? {
        videos.first { $0.id == selectedID }
    }

    /// Whether an import or wallpaper change is in progress.
    var isBusy: Bool { isImporting || isApplying }

    /// Opens local storage and loads saved wallpaper preferences.
    private init() {
        restoreOnLaunch = UserDefaults.standard.object(forKey: "restoreOnLaunch") as? Bool ?? true
        smoothLoop = UserDefaults.standard.bool(forKey: "smoothLoop")
        allowSound = UserDefaults.standard.bool(forKey: "allowSound")
        volume = UserDefaults.standard.object(forKey: "volume") == nil
            ? 1
            : min(max(UserDefaults.standard.double(forKey: "volume"), 0), 1)
        selectedID = UserDefaults.standard.string(forKey: "selectedVideoID").flatMap(UUID.init(uuidString:))
        engine.setSmoothLoop(smoothLoop)
        engine.setVolume(volume)
        engine.setSoundAllowed(allowSound)
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = support.appendingPathComponent("Loopmural/Videos", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.directory = directory
            container = try ModelContainer(for: WallpaperVideo.self)
            container?.mainContext.autosaveEnabled = false
            try refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
        engine.onFailure = { [weak self] message in
            self?.errorMessage = message
        }
    }

    /// Restores the saved wallpaper and pause state when enabled.
    func restoreWallpaper() async {
        guard restoreOnLaunch, let video = selectedVideo else { return }
        await apply(video, paused: defaults.bool(forKey: "wallpaperPaused"))
    }

    /// Opens a file picker to import MP4 or MOV videos.
    func chooseFiles() {
        guard !isBusy, importPanel == nil, container != nil else { return }
        errorMessage = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Import")
        panel.message = String(localized: "MP4 or MOV files are copied into your local Loopmural library.")
        importPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self else { return }
                importPanel = nil
                guard response == .OK else { return }
                await importFiles(panel.urls)
            }
        }
    }

    /// Starts the selected video and saves its playback preferences.
    func apply(_ video: WallpaperVideo, paused: Bool = false) async {
        guard !isApplying else { return }
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }
        do {
            let url = try videoURL(video)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw WallpaperError.missingFile
            }
            try await engine.start(url: url, paused: paused)
            selectedID = video.id
            defaults.set(video.id.uuidString, forKey: "selectedVideoID")
            defaults.set(paused, forKey: "wallpaperPaused")
        } catch is CancellationError {
            // A stop or shutdown superseded this request.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggles playback and saves the pause preference.
    func togglePaused() {
        engine.setPaused(!engine.isPaused)
        defaults.set(engine.isPaused, forKey: "wallpaperPaused")
    }

    /// Stops playback and clears the saved wallpaper selection.
    func stopWallpaper() {
        engine.stop()
        selectedID = nil
        defaults.removeObject(forKey: "selectedVideoID")
        defaults.removeObject(forKey: "wallpaperPaused")
    }

    /// Saves a nonempty display title without changing the video file.
    func rename(_ video: WallpaperVideo, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !title.isEmpty, let context = container?.mainContext else { return }
        errorMessage = nil
        video.name = title
        do {
            try context.save()
            pendingRename = nil
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }

    /// Saves a video's pin state without changing its import order or playback.
    func togglePinned(_ video: WallpaperVideo) {
        guard !isBusy, let context = container?.mainContext else { return }
        errorMessage = nil
        video.isPinned.toggle()
        do {
            try context.save()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
        updateVideoSections()
    }

    /// Deletes a video’s metadata and app-owned file.
    func remove(_ video: WallpaperVideo) {
        guard !isBusy, let context = container?.mainContext else { return }
        do {
            let url = try videoURL(video)
            let removedID = video.id
            context.delete(video)
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
            if selectedID == removedID {
                stopWallpaper()
            }
            pendingRemoval = nil
            try refresh()
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reloads video metadata and cached thumbnails from storage.
    private func refresh() throws {
        guard let context = container?.mainContext else { throw WallpaperError.libraryUnavailable }
        videos = try context.fetch(FetchDescriptor<WallpaperVideo>(
            sortBy: [SortDescriptor(\WallpaperVideo.importedAt, order: .reverse)]
        ))
        updateVideoSections()
        thumbnails = videos.reduce(into: [:]) { result, video in
            if let data = video.thumbnailData, let image = NSImage(data: data) {
                result[video.id] = image
            }
        }
    }

    /// Partitions the already sorted library when videos or pin states change.
    private func updateVideoSections() {
        pinnedVideos = videos.filter(\.isPinned)
        unpinnedVideos = videos.filter { !$0.isPinned }
    }

    /// Resolves the path to a video’s app-owned copy.
    private func videoURL(_ video: WallpaperVideo) throws -> URL {
        guard let directory else { throw WallpaperError.libraryUnavailable }
        return directory.appendingPathComponent(video.fileName)
    }

    /// Imports selected MP4 or MOV files and plays the last successfully imported video.
    private func importFiles(_ urls: [URL]) async {
        guard !isBusy, let context = container?.mainContext, let directory else { return }
        isImporting = true
        defer { isImporting = false }
        var failures: [String] = []
        var lastImportedVideo: WallpaperVideo?
        for source in urls {
            let scoped = source.startAccessingSecurityScopedResource()
            defer {
                if scoped { source.stopAccessingSecurityScopedResource() }
            }
            let id = UUID()
            let fileExtension = source.pathExtension.lowercased()
            let fileName = id.uuidString + "." + fileExtension
            let destination = directory.appendingPathComponent(fileName)
            var committed = false
            do {
                guard ["mp4", "mov"].contains(fileExtension) else { throw WallpaperError.invalidVideo }
                let values = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let identity = source.standardizedFileURL.path + ":" +
                    String(values.fileSize ?? 0) + ":" +
                    String(values.contentModificationDate?.timeIntervalSince1970 ?? 0)
                if videos.contains(where: { $0.sourceIdentity == identity }) { continue }

                // Large file copies run off the main actor so the menu remains responsive.
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.copyItem(at: source, to: destination)
                }.value

                let asset = AVURLAsset(url: destination)
                let playable = try await asset.load(.isPlayable)
                let duration = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard playable, !tracks.isEmpty, duration.seconds.isFinite, duration.seconds > 0 else {
                    throw WallpaperError.invalidVideo
                }
                let thumbnail = await makeThumbnail(asset: asset, duration: duration.seconds)
                let video = WallpaperVideo(
                    id: id,
                    name: source.deletingPathExtension().lastPathComponent,
                    fileName: fileName,
                    duration: duration.seconds,
                    sourceIdentity: identity,
                    thumbnailData: thumbnail
                )
                context.insert(video)
                do {
                    try context.save()
                    committed = true
                    lastImportedVideo = video
                } catch {
                    context.rollback()
                    throw error
                }
                try refresh()
            } catch {
                if !committed {
                    try? FileManager.default.removeItem(at: destination)
                }
                failures.append(source.lastPathComponent + ": " + error.localizedDescription)
            }
        }
        if let lastImportedVideo {
            await apply(lastImportedVideo)
        }
        if !failures.isEmpty {
            errorMessage = (failures + [errorMessage].compactMap(\.self)).joined(separator: "\n")
        }
    }

    /// Creates a PNG preview frame when video decoding succeeds.
    private func makeThumbnail(asset: AVAsset, duration: Double) async -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 405)
        do {
            let result = try await generator.image(at: CMTime(
                seconds: min(1, duration / 2),
                preferredTimescale: 600
            ))
            return NSBitmapImageRep(cgImage: result.image).representation(using: .png, properties: [:])
        } catch {
            // Missing thumbnails do not prevent a valid video from being imported.
            return nil
        }
    }
}
