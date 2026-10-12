import Foundation
import SwiftData

/// Metadata for an app-owned copy of an imported MP4.
@Model
final class WallpaperVideo {
    @Attribute(.unique) var id: UUID
    var name: String
    var fileName: String
    var importedAt: Date
    var duration: Double
    var sourceIdentity: String
    @Attribute(.externalStorage) var thumbnailData: Data?

    init(id: UUID, name: String, duration: Double, sourceIdentity: String, thumbnailData: Data?) {
        self.id = id
        self.name = name
        fileName = id.uuidString + ".mp4"
        importedAt = Date()
        self.duration = duration
        self.sourceIdentity = sourceIdentity
        self.thumbnailData = thumbnailData
    }
}
