import AppKit
import SwiftUI

/// Defines the menu bar popover and settings window.
@main
struct LoopmuralApp: App {
    /// Handles application lifecycle events.
    /// The shared video library and playback state.
    /// Manages launch at login preferences.
    @NSApplicationDelegateAdaptor(LoopmuralDelegate.self) private var delegate
    @State private var library = WallpaperLibrary.shared
    @State private var login = LaunchAtLoginManager()

    /// Creates the menu bar and settings scenes.
    var body: some Scene {
        MenuBarExtra {
            ContentView(library: library, login: login)
        } label: {
            Image(nsImage: LoopmuralIcon.menuBarImage)
                .renderingMode(.template)
                .accessibilityLabel("Loopmural")
                .background(OpenSettingsBridgeView())
        }
        .menuBarExtraStyle(.window)

        Settings {
            LoopmuralSettingsView(library: library, login: login)
        }
    }
}

/// Resolves SwiftUI's settings action even before the library popover opens.
private struct OpenSettingsBridgeView: View {
    /// Opens the SwiftUI settings window.
    @Environment(\.openSettings) private var openSettings

    /// Registers the settings action when the view appears.
    var body: some View {
        Color.clear
            .onAppear {
                MenuBarExtraRightClickMonitor.shared.onOpenSettings = {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
            }
    }
}

/// Handles app startup and shutdown.
@MainActor
final class LoopmuralDelegate: NSObject, NSApplicationDelegate {
    /// Starts menu bar monitoring and restores the last wallpaper.
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MenuBarExtraRightClickMonitor.shared.startMonitoring()
        Task { await WallpaperLibrary.shared.restoreWallpaper() }
    }

    /// Stops event monitoring and shuts down wallpaper playback.
    func applicationWillTerminate(_: Notification) {
        // Preserve the selected wallpaper and playback preference for next launch.
        MenuBarExtraRightClickMonitor.shared.stopMonitoring()
        WallpaperLibrary.shared.engine.shutdown()
    }
}
