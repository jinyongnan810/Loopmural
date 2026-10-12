import AppKit
import SwiftUI

@main
struct LoopmuralApp: App {
    @NSApplicationDelegateAdaptor(LoopmuralDelegate.self) private var delegate
    @State private var library = WallpaperLibrary.shared
    @State private var login = LaunchAtLoginManager()

    var body: some Scene {
        MenuBarExtra {
            ContentView(library: library, login: login)
        } label: {
            Label("Loopmural", systemImage: "play.rectangle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            LoopmuralSettingsView(library: library, login: login)
        }
    }
}

@MainActor
final class LoopmuralDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { await WallpaperLibrary.shared.restoreWallpaper() }
    }

    func applicationWillTerminate(_: Notification) {
        // Preserve the selected wallpaper and playback preference for next launch.
        WallpaperLibrary.shared.engine.shutdown()
    }
}
