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
    @Environment(\.openSettings) private var openSettings

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

@MainActor
final class LoopmuralDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MenuBarExtraRightClickMonitor.shared.startMonitoring()
        Task { await WallpaperLibrary.shared.restoreWallpaper() }
    }

    func applicationWillTerminate(_: Notification) {
        // Preserve the selected wallpaper and playback preference for next launch.
        MenuBarExtraRightClickMonitor.shared.stopMonitoring()
        WallpaperLibrary.shared.engine.shutdown()
    }
}
