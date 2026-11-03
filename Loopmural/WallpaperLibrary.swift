import AppKit
import AVFoundation
import Foundation
import Observation
import PhotosUI
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
    /// Invalidates visible thumbnails after a linked file is replaced.
    private(set) var thumbnailRevision = 0
    /// Whether a wallpaper change is in progress.
    private(set) var isApplying = false
    /// Whether imported videos are being deleted.
    private(set) var isDeleting = false
    /// The total size of app-owned video files, excluding metadata and thumbnails.
    private(set) var importedVideoBytes: Int64?
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

    /// Whether newly added videos are copied instead of linked.
    var copyVideosIntoLibrary: Bool {
        didSet { defaults.set(copyVideosIntoLibrary, forKey: "copyVideosIntoLibrary") }
    }

    /// The linked video whose access needs to be restored.
    private(set) var unavailableVideoID: UUID?

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
    @ObservationIgnored private var photosPickerWindow: NSWindow?
    @ObservationIgnored private var photosPickerCoordinator: PhotosPickerCoordinator?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var thumbnailStore: Task<WallpaperThumbnailStore, Never>?
    @ObservationIgnored private var storageUsageTask: Task<Int64?, Never>?
    @ObservationIgnored private var storageUsageGeneration = UUID()
    @ObservationIgnored private let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    /// The library video matching the selected identifier.
    var selectedVideo: WallpaperVideo? {
        videos.first { $0.id == selectedID }
    }

    /// Whether an import, wallpaper change, or library deletion is in progress.
    var isBusy: Bool { isImporting || isApplying || isDeleting }

    /// Opens local storage and loads saved wallpaper preferences.
    private init() {
        restoreOnLaunch = UserDefaults.standard.object(forKey: "restoreOnLaunch") as? Bool ?? true
        copyVideosIntoLibrary = UserDefaults.standard.bool(forKey: "copyVideosIntoLibrary")
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
            if let container {
                // Construct the model actor off the main thread so its context uses
                // a background executor for external thumbnail-data reads.
                thumbnailStore = Task.detached(priority: .utility) {
                    WallpaperThumbnailStore(modelContainer: container)
                }
            }
            container?.mainContext.autosaveEnabled = false
            try refresh()
            refreshStorageUsage()
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
        guard !isBusy, importPanel == nil, photosPickerWindow == nil, container != nil else { return }
        errorMessage = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Add Videos")
        panel.message = copyVideosIntoLibrary
            ? String(localized: "MP4 or MOV files are copied into your local Loopmural library.")
            : String(localized: "Videos stay in their original location. Keep them available for wallpaper playback.")
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

    /// Opens the system Photos picker to import videos from the user's photo library.
    func choosePhotos() {
        guard !isBusy, importPanel == nil, photosPickerWindow == nil, container != nil else { return }
        errorMessage = nil
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos
        configuration.selectionLimit = 0
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        let coordinator = PhotosPickerCoordinator(
            onFinish: { [weak self] results in
                guard let self else { return }
                closePhotosPicker()
                guard !results.isEmpty else { return }
                Task { @MainActor [weak self] in
                    await self?.importPhotoResults(results)
                }
            },
            onCancel: { [weak self] in
                self?.closePhotosPicker()
            }
        )
        picker.delegate = coordinator

        let window = NSWindow(contentViewController: picker)
        window.title = String(localized: "Choose from Photos")
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 520))
        window.minSize = NSSize(width: 560, height: 400)
        window.isReleasedWhenClosed = false
        window.delegate = coordinator
        window.center()

        photosPickerCoordinator = coordinator
        photosPickerWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closePhotosPicker() {
        guard let window = photosPickerWindow else {
            photosPickerCoordinator = nil
            return
        }
        photosPickerWindow = nil
        photosPickerCoordinator = nil
        window.delegate = nil
        window.close()
    }

    /// Starts the selected video and saves its playback preferences.
    func apply(_ video: WallpaperVideo, paused: Bool = false) async {
        guard !isApplying, !isDeleting else { return }
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }
        do {
            let url = try videoURL(video)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw WallpaperError.missingFile
            }
            try await engine.start(url: url, paused: paused)
            unavailableVideoID = nil
            selectedID = video.id
            defaults.set(video.id.uuidString, forKey: "selectedVideoID")
            defaults.set(paused, forKey: "wallpaperPaused")
        } catch is CancellationError {
            // A stop or shutdown superseded this request.
        } catch {
            if video.isLinked { unavailableVideoID = video.id }
            errorMessage = error.localizedDescription
        }
    }

    /// Restores access to a linked original after it moves or becomes unavailable.
    func locateFile(_ video: WallpaperVideo) {
        guard video.isLinked, !isBusy, importPanel == nil, photosPickerWindow == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Locate File")
        panel.message = String(localized: "Select the original video to restore access to this library entry.")
        importPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self else { return }
                importPanel = nil
                guard response == .OK, let url = panel.url,
                      videos.contains(where: { $0.id == video.id }) else { return }
                await relink(video, to: url)
            }
        }
    }

    private func relink(_ video: WallpaperVideo, to url: URL) async {
        guard !isBusy, let context = container?.mainContext else { return }
        isImporting = true
        defer { isImporting = false }
        errorMessage = nil
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let asset = AVURLAsset(url: url)
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard playable, !tracks.isEmpty, duration.seconds.isFinite, duration.seconds > 0 else {
                throw WallpaperError.invalidVideo
            }
            let bookmark = try Self.bookmark(for: url)
            let identity = try await Self.sourceIdentity(for: url)
            let thumbnail = await Self.makeThumbnail(url: url, duration: duration.seconds)
            video.bookmarkData = bookmark
            video.sourceIdentity = identity
            video.duration = duration.seconds
            video.thumbnailData = thumbnail
            try context.save()
            thumbnailCache.removeObject(forKey: thumbnailKey(video.id, maximumPixelSize: 160))
            thumbnailCache.removeObject(forKey: thumbnailKey(video.id, maximumPixelSize: 720))
            thumbnailRevision += 1
            unavailableVideoID = nil
            await apply(video)
        } catch {
            context.rollback()
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

    /// Removes an entry and its app-owned copy, preserving linked originals.
    func remove(_ video: WallpaperVideo) async {
        guard !isBusy, let context = container?.mainContext else { return }
        isDeleting = true
        defer {
            refreshStorageUsage()
            isDeleting = false
        }
        do {
            let url = video.isLinked ? nil : try videoURL(video)
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
            if unavailableVideoID == removedID { unavailableVideoID = nil }
            videos.removeAll { $0.id == removedID }
            thumbnailCache.removeObject(forKey: thumbnailKey(removedID, maximumPixelSize: 160))
            thumbnailCache.removeObject(forKey: thumbnailKey(removedID, maximumPixelSize: 720))
            updateVideoSections()
            try await Task.detached(priority: .userInitiated) {
                if let url, FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }.value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Measures all copies in the owned video folder, including leftovers from failed deletions.
    func refreshStorageUsage() {
        storageUsageTask?.cancel()
        let request = UUID()
        storageUsageGeneration = request
        guard let directory else {
            storageUsageTask = nil
            importedVideoBytes = nil
            return
        }
        let task = Task.detached(priority: .utility) { () -> Int64? in
            do {
                let files = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.fileSizeKey]
                )
                return try files.reduce(Int64(0)) { total, url in
                    try Task.checkCancellation()
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    return total + Int64(values.fileSize ?? 0)
                }
            } catch {
                return nil
            }
        }
        storageUsageTask = task
        Task { @MainActor [weak self] in
            let bytes = await task.value
            guard let self, storageUsageGeneration == request else { return }
            importedVideoBytes = bytes
            storageUsageTask = nil
        }
    }

    /// Removes all library entries and app-owned copies while preserving source files.
    func deleteAllImportedVideos() async {
        guard !isBusy, let context = container?.mainContext, let directory else { return }
        isDeleting = true
        errorMessage = nil
        defer {
            refreshStorageUsage()
            isDeleting = false
        }
        do {
            // List files before changing metadata so an unreadable folder leaves the library intact.
            let files = try await Task.detached(priority: .userInitiated) {
                try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            }.value
            for video in videos {
                context.delete(video)
            }
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
            stopWallpaper()
            unavailableVideoID = nil
            pendingRemoval = nil
            pendingRename = nil
            videos.removeAll()
            pinnedVideos.removeAll()
            unpinnedVideos.removeAll()
            thumbnailCache.removeAllObjects()

            // Keep Settings responsive and try every file even if one cannot be removed.
            let failures = await Task.detached(priority: .userInitiated) {
                var failures: [String] = []
                for file in files {
                    do {
                        try FileManager.default.removeItem(at: file)
                    } catch {
                        failures.append(file.lastPathComponent + ": " + error.localizedDescription)
                    }
                }
                return failures
            }.value
            if !failures.isEmpty {
                errorMessage = String(localized: "Some video copies could not be deleted. Try clearing the library again.")
                    + "\n" + failures.joined(separator: "\n")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reloads metadata without reading external thumbnail blobs.
    private func refresh() throws {
        guard let context = container?.mainContext else { throw WallpaperError.libraryUnavailable }
        videos = try context.fetch(FetchDescriptor<WallpaperVideo>(
            sortBy: [SortDescriptor(\WallpaperVideo.importedAt, order: .reverse)]
        ))
        updateVideoSections()
    }

    /// Loads only requested images, retaining visible previews independently of eviction.
    func thumbnail(for id: UUID, maximumPixelSize: Int) async -> NSImage? {
        let key = thumbnailKey(id, maximumPixelSize: maximumPixelSize)
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let thumbnailStore else { return nil }
        let store = await thumbnailStore.value
        guard !Task.isCancelled else { return nil }
        guard let bitmap = await store.image(for: id, maximumPixelSize: maximumPixelSize),
              !Task.isCancelled, videos.contains(where: { $0.id == id }) else { return nil }
        // Another visible view may have requested this image while we awaited decoding.
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let image = NSImage(cgImage: bitmap, size: .zero)
        thumbnailCache.setObject(image, forKey: key, cost: bitmap.bytesPerRow * bitmap.height)
        return image
    }

    private func thumbnailKey(_ id: UUID, maximumPixelSize: Int) -> NSString {
        (id.uuidString + "-" + String(maximumPixelSize)) as NSString
    }

    /// Partitions the already sorted library when videos or pin states change.
    private func updateVideoSections() {
        pinnedVideos = videos.filter(\.isPinned)
        unpinnedVideos = videos.filter { !$0.isPinned }
    }

    /// Resolves either a persistent bookmark or an existing app-owned copy.
    private func videoURL(_ video: WallpaperVideo) throws -> URL {
        if let bookmark = video.bookmarkData {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                video.bookmarkData = try Self.bookmark(for: url)
                do { try container?.mainContext.save() } catch {
                    container?.mainContext.rollback()
                    throw error
                }
            }
            return url
        }
        guard let directory else { throw WallpaperError.libraryUnavailable }
        return directory.appendingPathComponent(video.fileName)
    }

    private static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                             includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private nonisolated static func sourceIdentity(for source: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let values = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return source.standardizedFileURL.path + ":" + String(values.fileSize ?? 0) + ":" +
                String(values.contentModificationDate?.timeIntervalSince1970 ?? 0)
        }.value
    }

    /// Imports selected MP4 or MOV files and plays the last successfully imported video.
    private func importFiles(_ urls: [URL]) async {
        guard !isBusy, let context = container?.mainContext, let directory else { return }
        isImporting = true
        defer {
            refreshStorageUsage()
            isImporting = false
        }
        let shouldCopy = copyVideosIntoLibrary
        var failures: [String] = []
        var lastImportedVideo: WallpaperVideo?
        var importedVideos: [WallpaperVideo] = []
        var sourceIdentities = Set(videos.map(\.sourceIdentity))
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
                let identity = try await Self.sourceIdentity(for: source)
                if sourceIdentities.contains(identity) { continue }

                let bookmark = shouldCopy ? nil : try Self.bookmark(for: source)
                if shouldCopy {
                    // Large file copies run off the main actor so the menu remains responsive.
                    try await Task.detached(priority: .userInitiated) {
                        try FileManager.default.copyItem(at: source, to: destination)
                    }.value
                }
                let playbackURL = shouldCopy ? destination : source
                let asset = AVURLAsset(url: playbackURL)
                let playable = try await asset.load(.isPlayable)
                let duration = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard playable, !tracks.isEmpty, duration.seconds.isFinite, duration.seconds > 0 else {
                    throw WallpaperError.invalidVideo
                }
                let thumbnail = await Self.makeThumbnail(url: playbackURL, duration: duration.seconds)
                let video = WallpaperVideo(
                    id: id,
                    name: source.deletingPathExtension().lastPathComponent,
                    fileName: fileName,
                    duration: duration.seconds,
                    sourceIdentity: identity,
                    thumbnailData: thumbnail,
                    bookmarkData: bookmark
                )
                context.insert(video)
                do {
                    try context.save()
                    committed = true
                    lastImportedVideo = video
                    importedVideos.append(video)
                    sourceIdentities.insert(identity)
                } catch {
                    context.rollback()
                    throw error
                }
            } catch {
                if !committed, shouldCopy {
                    await Task.detached(priority: .utility) {
                        try? FileManager.default.removeItem(at: destination)
                    }.value
                }
                failures.append(source.lastPathComponent + ": " + error.localizedDescription)
            }
        }
        videos.insert(contentsOf: importedVideos.reversed(), at: 0)
        updateVideoSections()
        if let lastImportedVideo {
            await apply(lastImportedVideo)
        }
        if !failures.isEmpty {
            errorMessage = (failures + [errorMessage].compactMap(\.self)).joined(separator: "\n")
        }
    }

    /// Creates a PNG preview frame when video decoding succeeds.
    private nonisolated static func makeThumbnail(url: URL, duration: Double) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
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
        }.value
    }

    private enum PhotoImportResult: Sendable {
        case duplicate
        case imported(fileName: String, displayName: String, identity: String)
    }

    private struct UncheckedItemProvider: @unchecked Sendable {
        let provider: NSItemProvider
        let assetIdentifier: String?
        let fallbackLabel: String
    }

    /// Copies a selected Photos video representation into the library directory before the temporary file expires.
    private nonisolated static func loadPhotoVideo(
        item: UncheckedItemProvider,
        id: UUID,
        directory: URL,
        existingIdentities: Set<String>
    ) async throws -> PhotoImportResult {
        let provider = item.provider
        let typeIdentifier: String
        if provider.hasItemConformingToTypeIdentifier(UTType.mpeg4Movie.identifier) {
            typeIdentifier = UTType.mpeg4Movie.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.quickTimeMovie.identifier) {
            typeIdentifier = UTType.quickTimeMovie.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            typeIdentifier = UTType.movie.identifier
        } else {
            throw WallpaperError.invalidVideo
        }

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: WallpaperError.invalidVideo)
                    return
                }
                do {
                    let rawExtension = url.pathExtension.lowercased()
                    let fileExtension: String
                    if ["mp4", "mov"].contains(rawExtension) {
                        fileExtension = rawExtension
                    } else if typeIdentifier == UTType.mpeg4Movie.identifier {
                        fileExtension = "mp4"
                    } else if typeIdentifier == UTType.quickTimeMovie.identifier {
                        fileExtension = "mov"
                    } else {
                        throw WallpaperError.invalidVideo
                    }

                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    let identity = if let assetIdentifier = item.assetIdentifier, !assetIdentifier.isEmpty {
                        "photos:" + assetIdentifier
                    } else {
                        "photos:" + url.lastPathComponent.lowercased() + ":" + String(values.fileSize ?? 0)
                    }
                    if existingIdentities.contains(identity) {
                        continuation.resume(returning: .duplicate)
                        return
                    }

                    let fileName = id.uuidString + "." + fileExtension
                    let destination = directory.appendingPathComponent(fileName)
                    try FileManager.default.copyItem(at: url, to: destination)

                    let baseName = url.deletingPathExtension().lastPathComponent
                    let displayName = baseName.isEmpty ? item.fallbackLabel : baseName
                    continuation.resume(returning: .imported(
                        fileName: fileName,
                        displayName: displayName,
                        identity: identity
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Imports videos selected from Photos into local library storage and plays the last imported video.
    private func importPhotoResults(_ results: [PHPickerResult]) async {
        guard !isBusy, let context = container?.mainContext, let directory else { return }
        isImporting = true
        defer {
            refreshStorageUsage()
            isImporting = false
        }
        var failures: [String] = []
        var lastImportedVideo: WallpaperVideo?
        var importedVideos: [WallpaperVideo] = []
        var sourceIdentities = Set(videos.map(\.sourceIdentity))

        for result in results {
            let id = UUID()
            let fallbackLabel = result.itemProvider.suggestedName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (fallbackLabel?.isEmpty == false) ? fallbackLabel! : String(localized: "Photos Video")
            let item = UncheckedItemProvider(
                provider: result.itemProvider,
                assetIdentifier: result.assetIdentifier,
                fallbackLabel: label
            )
            var copiedDestination: URL?
            var committed = false
            do {
                let loaded = try await Self.loadPhotoVideo(
                    item: item,
                    id: id,
                    directory: directory,
                    existingIdentities: sourceIdentities
                )
                guard case let .imported(fileName, displayName, identity) = loaded else {
                    continue
                }
                let destination = directory.appendingPathComponent(fileName)
                copiedDestination = destination

                let asset = AVURLAsset(url: destination)
                let playable = try await asset.load(.isPlayable)
                let duration = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard playable, !tracks.isEmpty, duration.seconds.isFinite, duration.seconds > 0 else {
                    throw WallpaperError.invalidVideo
                }
                let thumbnail = await Self.makeThumbnail(url: destination, duration: duration.seconds)
                let video = WallpaperVideo(
                    id: id,
                    name: displayName,
                    fileName: fileName,
                    duration: duration.seconds,
                    sourceIdentity: identity,
                    thumbnailData: thumbnail,
                    bookmarkData: nil
                )
                context.insert(video)
                do {
                    try context.save()
                    committed = true
                    lastImportedVideo = video
                    importedVideos.append(video)
                    sourceIdentities.insert(identity)
                } catch {
                    context.rollback()
                    throw error
                }
            } catch {
                if !committed, let copiedDestination {
                    await Task.detached(priority: .utility) {
                        try? FileManager.default.removeItem(at: copiedDestination)
                    }.value
                }
                failures.append(label + ": " + error.localizedDescription)
            }
        }
        videos.insert(contentsOf: importedVideos.reversed(), at: 0)
        updateVideoSections()
        if let lastImportedVideo {
            await apply(lastImportedVideo)
        }
        if !failures.isEmpty {
            errorMessage = (failures + [errorMessage].compactMap(\.self)).joined(separator: "\n")
        }
    }
}

/// Bridges PHPickerViewController and window dismissal callbacks back to the library.
@MainActor
private final class PhotosPickerCoordinator: NSObject, PHPickerViewControllerDelegate, NSWindowDelegate {
    private let onFinish: ([PHPickerResult]) -> Void
    private let onCancel: () -> Void

    init(onFinish: @escaping ([PHPickerResult]) -> Void, onCancel: @escaping () -> Void) {
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    nonisolated func picker(_: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let box = UncheckedPickerResults(results: results)
        Task { @MainActor [weak self] in
            self?.onFinish(box.results)
        }
    }

    func windowWillClose(_: Notification) {
        onCancel()
    }
}

private struct UncheckedPickerResults: @unchecked Sendable {
    let results: [PHPickerResult]
}
