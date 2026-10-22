import AppKit
import SwiftUI

/// Shows startup preferences and playback information.
struct LoopmuralSettingsView: View {
    /// The shared video library and playback state.
    /// Manages launch at login preferences.
    @Bindable var library: WallpaperLibrary
    let login: LaunchAtLoginManager

    /// Builds startup, playback, storage, and privacy settings.
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

            Section("Playback") {
                Toggle("Smooth Loop", isOn: $library.smoothLoop)
                    .disabled(library.isBusy)
                Text("Blend the end of each video into its beginning. Leave off for videos that already loop seamlessly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Allow Sound", isOn: $library.allowSound)
                if library.allowSound {
                    Slider(value: $library.volume, in: 0 ... 1) {
                        Text("Volume")
                    }
                    .accessibilityValue(library.volume.formatted(.percent.precision(.fractionLength(0))))
                }
                LabeledContent("Displays") {
                    Text("All connected displays")
                }
                LabeledContent("Sizing") {
                    Text("Fill screen")
                }
                Text("Playback pauses while your displays sleep or your user session is inactive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LibraryStorageSettingsSection(library: library)

            PrivacySettingsSection()
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 580)
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
        }
    }
}

/// Shows the space used by imported videos and provides confirmed library cleanup.
private struct LibraryStorageSettingsSection: View {
    @Bindable var library: WallpaperLibrary
    @State private var confirmsDeletion = false

    var body: some View {
        Section("Storage") {
            Toggle("Copy Videos into Library", isOn: $library.copyVideosIntoLibrary)
                .disabled(library.isBusy)
            Text("New videos are linked to their original files to save space. Keep those files available. Turn on to store independent copies. Existing videos are unchanged.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Video Copy Storage") {
                if let bytes = library.importedVideoBytes {
                    Text(bytes, format: .byteCount(style: .file))
                } else {
                    Text("Unavailable")
                }
            }
            Text("This size includes video copies stored by Loopmural. Linked originals, thumbnails, and metadata are excluded.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Clear Library…", role: .destructive) {
                confirmsDeletion = true
            }
            .disabled(library.isBusy)
            Text("To free this space before uninstalling Loopmural, delete your library here. Your original videos won’t be affected.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if library.isDeleting {
                ProgressView("Clearing library…")
                    .controlSize(.small)
            }
            if let message = library.errorMessage {
                ErrorBanner(message: message) { library.errorMessage = nil }
            }
        }
        .onAppear { library.refreshStorageUsage() }
        .alert("Clear Library?", isPresented: $confirmsDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Library", role: .destructive) {
                Task { await library.deleteAllImportedVideos() }
            }
        } message: {
            Text("This permanently removes all library entries, thumbnails, and video copies stored by Loopmural, and stops wallpaper playback. Linked originals and other source files won’t be deleted. This cannot be undone.")
        }
    }
}

/// Shows privacy information and the policy link.
private struct PrivacySettingsSection: View {
    /// The locale used to choose the privacy policy language.
    @Environment(\.locale) private var locale

    /// Builds the privacy notice and policy link.
    var body: some View {
        Section("Privacy & Security") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your videos and library data stay on your Mac. Loopmural does not upload your videos or include tracking or analytics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(destination: privacyPolicyURL) {
                    Label("View Privacy Policy", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }
        }
    }

    /// The privacy policy link for the current language.
    private var privacyPolicyURL: URL {
        let fileName = locale.language.languageCode?.identifier == "ja"
            ? "PRIVACY_POLICY_JA.md"
            : "PRIVACY_POLICY.md"
        return URL(string: "https://github.com/jinyongnan810/Loopmural/blob/main/")!
            .appendingPathComponent(fileName)
    }
}
