import Foundation
import SwiftData

/// Metadata for an app-owned copy of an imported video.
@Model
final class WallpaperVideo {
    /// The stable, unique identifier for this video.
    /// The video name shown to the user.
    @Attribute(.unique) var id: UUID
    var name: String
    /// The filename of the app-owned video copy, including its original format’s extension.
    var fileName: String
    /// The date this video was added to the library.
    var importedAt: Date
    /// The video’s playback duration in seconds.
    var duration: Double
    /// Identifies the source file to avoid duplicate imports.
    var sourceIdentity: String
    /// The saved PNG thumbnail, when available.
    @Attribute(.externalStorage) var thumbnailData: Data?

    /// Creates metadata for a newly imported video.
    init(id: UUID, name: String, fileName: String, duration: Double, sourceIdentity: String, thumbnailData: Data?) {
        self.id = id
        self.name = name
        self.fileName = fileName
        importedAt = Date()
        self.duration = duration
        self.sourceIdentity = sourceIdentity
        self.thumbnailData = thumbnailData
    }
}
