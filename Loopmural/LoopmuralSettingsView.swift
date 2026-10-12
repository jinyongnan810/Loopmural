import AppKit
import SwiftUI

struct LoopmuralSettingsView: View {
    @Bindable var library: WallpaperLibrary
    let login: LaunchAtLoginManager

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { login.isEnabled },
                    set: { login.setEnabled($0) }
                ))
                Text("Start Loopmural automatically when you sign in to your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if login.needsApproval {
                    Text("Allow Loopmural in System Settings to finish enabling launch at login.")
                        .font(.caption)
                    Button("Open Login Items Settings") {
                        login.openLoginSettings()
                    }
                }
                if let message = login.errorMessage {
                    ErrorBanner(message: message) { login.errorMessage = nil }
                }
                Toggle("Restore Last Wallpaper", isOn: $library.restoreOnLaunch)
                Text("Restore your last selected video when Loopmural opens. A paused wallpaper stays paused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Playback & Storage") {
                LabeledContent("Audio", value: "Always muted")
                LabeledContent("Displays", value: "All connected displays")
                LabeledContent("Sizing", value: "Fill screen")
                Text("Playback pauses while your displays sleep or your user session is inactive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Imported MP4 files are copied into Loopmural’s local storage. Removing a video deletes only that copy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 470)
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
        }
    }
}
