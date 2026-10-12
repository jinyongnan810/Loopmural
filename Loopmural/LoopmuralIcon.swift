import AppKit

/// Creates template icons for the app and menu bar.
@MainActor
enum LoopmuralIcon {
    /// The combined template icon for the library header.
    static let image: NSImage = {
        let screen = NSImage(resource: .loopmuralScreen)
        let loop = NSImage(resource: .loopmuralLoop)
        let icon = NSImage(size: NSSize(width: 28, height: 20), flipped: false) { _ in
            // Crop the transparent margins around the original 1024-point logo.
            let bounds = NSRect(x: -6.12, y: -10.04, width: 40.16, height: 40.16)
            screen.draw(in: bounds)
            loop.draw(in: bounds)
            return true
        }
        icon.isTemplate = true
        return icon
    }()

    /// The smaller template icon sized for the menu bar.
    static let menuBarImage: NSImage = {
        let icon = (image.copy() as? NSImage) ?? image
        icon.size = NSSize(width: 18, height: 13)
        icon.isTemplate = true
        return icon
    }()
}
