import AppKit
import AVFoundation
import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

@MainActor
@Observable
final class WallpaperLibrary {
    static let shared = WallpaperLibrary()

    private(set) var videos: [WallpaperVideo] = []
    private(set) var selectedID: UUID?
    private(set) var isImporting = false
    private(set) var isApplying = false
    private(set) var thumbnails: [UUID: NSImage] = [:]
    var errorMessage: String?
    var pendingRemoval: WallpaperVideo?
    let engine = WallpaperEngine()
    var restoreOnLaunch: Bool {
        didSet { UserDefaults.standard.set(restoreOnLaunch, forKey: "restoreOnLaunch") }
    }

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private var importPanel: NSOpenPanel?
    @ObservationIgnored private let defaults = UserDefaults.standard

    var selectedVideo: WallpaperVideo? {
        videos.first { $0.id == selectedID }
    }

    var isBusy: Bool { isImporting || isApplying }

    private init() {
        restoreOnLaunch = UserDefaults.standard.object(forKey: "restoreOnLaunch") as? Bool ?? true
        selectedID = UserDefaults.standard.string(forKey: "selectedVideoID").flatMap(UUID.init(uuidString:))
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

    func restoreWallpaper() async {
        guard restoreOnLaunch, let video = selectedVideo else { return }
        await apply(video, paused: defaults.bool(forKey: "wallpaperPaused"))
    }

    func chooseFiles() {
        guard !isBusy, importPanel == nil, container != nil else { return }
        errorMessage = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Import")
        panel.message = String(localized: "MP4 files are copied into your local Loopmural library.")
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

    func togglePaused() {
        engine.setPaused(!engine.isPaused)
        defaults.set(engine.isPaused, forKey: "wallpaperPaused")
    }

    func stopWallpaper() {
        engine.stop()
        selectedID = nil
        defaults.removeObject(forKey: "selectedVideoID")
        defaults.removeObject(forKey: "wallpaperPaused")
    }

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

    private func refresh() throws {
        guard let context = container?.mainContext else { throw WallpaperError.libraryUnavailable }
        videos = try context.fetch(FetchDescriptor<WallpaperVideo>(
            sortBy: [SortDescriptor(\WallpaperVideo.importedAt, order: .reverse)]
        ))
        thumbnails = videos.reduce(into: [:]) { result, video in
            if let data = video.thumbnailData, let image = NSImage(data: data) {
                result[video.id] = image
            }
        }
    }

    private func videoURL(_ video: WallpaperVideo) throws -> URL {
        guard let directory else { throw WallpaperError.libraryUnavailable }
        return directory.appendingPathComponent(video.fileName)
    }

    private func importFiles(_ urls: [URL]) async {
        guard !isBusy, let context = container?.mainContext, let directory else { return }
        isImporting = true
        defer { isImporting = false }
        var failures: [String] = []
        for source in urls {
            let scoped = source.startAccessingSecurityScopedResource()
            defer {
                if scoped { source.stopAccessingSecurityScopedResource() }
            }
            let id = UUID()
            let destination = directory.appendingPathComponent(id.uuidString + ".mp4")
            var committed = false
            do {
                guard source.pathExtension.lowercased() == "mp4" else { throw WallpaperError.invalidVideo }
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
                    duration: duration.seconds,
                    sourceIdentity: identity,
                    thumbnailData: thumbnail
                )
                context.insert(video)
                do {
                    try context.save()
                    committed = true
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
        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
    }

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
