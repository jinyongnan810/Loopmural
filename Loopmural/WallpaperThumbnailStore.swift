import Foundation
import ImageIO
import SwiftData

/// Reads persisted thumbnail blobs and decodes them away from the UI executor.
@ModelActor
actor WallpaperThumbnailStore {
    func image(for id: UUID, maximumPixelSize: Int) -> CGImage? {
        var descriptor = FetchDescriptor<WallpaperVideo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        // A short-lived context releases fetched models and external data after
        // each request, and sees imports and deletions saved by the UI context.
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        guard let video = try? context.fetch(descriptor).first,
              let data = video.thumbnailData,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }
}
