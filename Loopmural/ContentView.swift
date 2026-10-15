import AppKit
import SwiftUI

#Preview("Menu Bar") {
    ContentView(library: .shared, login: LaunchAtLoginManager())
}

/// Shows the wallpaper library in the menu bar popover.
struct ContentView: View {
    /// The shared video library and playback state.
    let library: WallpaperLibrary
    /// Manages launch at login preferences.
    let login: LaunchAtLoginManager

    /// Builds the library popover and video editing overlays.
    var body: some View {
        VStack(spacing: 0) {
            LibraryHeader(isImporting: library.isImporting, isBusy: library.isBusy) {
                library.chooseFiles()
            }
            Divider()
            LibraryScrollView(library: library)
            Divider()
            LibraryFooter(count: library.videos.count)
        }
        .frame(width: 420, height: 580)
        .liquidGlassEffect(in: Rectangle())
        .disabled(library.pendingRemoval != nil || library.pendingRename != nil)
        .overlay {
            if let video = library.pendingRemoval {
                RemoveVideoOverlay(name: video.name) {
                    library.remove(video)
                } onCancel: {
                    library.pendingRemoval = nil
                }
            } else if let video = library.pendingRename {
                RenameVideoOverlay(name: video.name, error: library.errorMessage, isBusy: library.isBusy) { title in
                    library.rename(video, to: title)
                } onCancel: {
                    library.pendingRename = nil
                }
                .id(video.id)
            }
        }
        .onAppear { login.refresh() }
    }
}

/// Shows the library content with a floating shortcut back to the top.
private struct LibraryScrollView: View {
    let library: WallpaperLibrary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isScrolledDown = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NowPlayingView(library: library)
                    if let error = library.errorMessage {
                        ErrorBanner(message: error) { library.errorMessage = nil }
                    }
                    VideoLibraryView(library: library)
                }
                .padding(16)
                .id("libraryTop")
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 20
            } action: { _, isScrolledDown in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    self.isScrolledDown = isScrolledDown
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isScrolledDown {
                    ScrollToTopButton {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            proxy.scrollTo("libraryTop", anchor: .top)
                        }
                    }
                    .padding(14)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
}

/// Matches C2V's circular glass button and hover feedback.
private struct ScrollToTopButton: View {
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isHovered ? Color.accentColor : .primary)
                .frame(width: 32, height: 32)
                .liquidGlassEffect(in: Circle())
                .scaleEffect(isHovered && !reduceMotion ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                self.isHovered = isHovered
            }
        }
        .help("Go to Top")
        .accessibilityLabel("Scroll to top")
        .accessibilityHint("Scrolls the wallpaper library back to the top")
    }
}

/// Shows the app title, import button, and settings shortcut.
private struct LibraryHeader: View {
    /// Opens the SwiftUI settings window.
    @Environment(\.openSettings) private var openSettings

    /// Whether video imports are in progress.
    let isImporting: Bool
    /// Whether an import or wallpaper change is in progress.
    let isBusy: Bool
    /// Opens the video import flow.
    let onImport: () -> Void

    /// Builds the title and import and settings controls.
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: LoopmuralIcon.image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Loopmural").font(.headline)
                Text("A little motion for your desktop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isImporting {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Importing videos")
            }
            Button(action: onImport) {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
                    .liquidGlassEffect(in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .help("Import MP4 or MOV files")
            .accessibilityLabel("Import MP4 or MOV files")
            Button {
                // Activate before opening, matching C2V’s settings presentation.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 28, height: 28)
                    .liquidGlassEffect(in: Circle())
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            .buttonStyle(.plain)
        }
        .padding(16)
        .liquidGlassEffect(in: Rectangle())
    }
}

/// Shows the current wallpaper and playback controls.
private struct NowPlayingView: View {
    /// The shared video library and playback state.
    let library: WallpaperLibrary

    /// Builds the current wallpaper preview and playback controls.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ON YOUR DESKTOP")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                if library.isApplying {
                    ProgressView().controlSize(.mini)
                } else if library.engine.hasWallpaper {
                    if library.engine.isPaused {
                        Label("Paused", systemImage: "pause.circle.fill")
                            .foregroundStyle(.secondary)
                    } else if library.engine.isSuspended {
                        Label("Sleeping", systemImage: "moon.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Playing", systemImage: "circle.fill")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .font(.caption)

            if let video = library.selectedVideo {
                VideoThumbnail(image: library.thumbnails[video.id])
                    .frame(height: 136)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                HStack {
                    Text(video.name)
                        .font(.headline)
                        .lineLimit(1)
                        .help(video.name)
                    Spacer()
                    if library.engine.hasWallpaper {
                        Button {
                            library.togglePaused()
                        } label: {
                            Image(systemName: library.engine.isPaused ? "play.fill" : "pause.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        .help(library.engine.isPaused ? Text("Resume wallpaper") : Text("Pause wallpaper"))
                        .accessibilityLabel(library.engine.isPaused ? Text("Resume wallpaper") : Text("Pause wallpaper"))
                        .disabled(library.isApplying)
                        Button {
                            library.stopWallpaper()
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .help("Stop wallpaper")
                        .accessibilityLabel("Stop wallpaper")
                    } else {
                        Button("Set Wallpaper") {
                            Task { await library.apply(video) }
                        }
                        .disabled(library.isBusy)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "desktopcomputer")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Your desktop, brought to life")
                        .font(.headline)
                    Text("Import an MP4 or MOV, then set it as your wallpaper.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            }
        }
        .padding(14)
        .liquidGlassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Lists imported videos or an import prompt.
private struct VideoLibraryView: View {
    /// The shared video library and playback state.
    let library: WallpaperLibrary

    /// Builds the video list or empty-library prompt.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR VIDEOS").font(.caption).fontWeight(.semibold)
                Spacer()
                Text(library.videos.count, format: .number).font(.caption).monospacedDigit()
            }
            .foregroundStyle(.secondary)
            if library.videos.isEmpty {
                Button {
                    library.chooseFiles()
                } label: {
                    Label("Import MP4 or MOV Files…", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .disabled(library.isBusy)
                Text("Videos are copied locally. Your original files stay untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(library.videos) { video in
                        VideoRow(
                            video: video,
                            image: library.thumbnails[video.id],
                            isSelected: library.selectedID == video.id,
                            isBusy: library.isBusy,
                            onSet: {
                                Task {
                                    guard library.selectedID != video.id else { return }
                                    await library.apply(video)
                                }
                            },
                            onRemove: { library.pendingRemoval = video },
                            onRename: {
                                library.errorMessage = nil
                                library.pendingRename = video
                            }
                        )
                    }
                }
            }
        }
    }
}

/// Shows a selectable video preview with an item menu.
private struct VideoRow: View {
    /// The library video shown in this row.
    let video: WallpaperVideo
    /// The thumbnail image, when available.
    let image: NSImage?
    /// Whether this video is the selected wallpaper.
    let isSelected: Bool
    /// Whether an import or wallpaper change is in progress.
    let isBusy: Bool
    /// Sets this video as the wallpaper.
    let onSet: () -> Void
    /// Requests removal of this video.
    let onRemove: () -> Void
    /// Requests a new title for this video.
    let onRename: () -> Void
    /// Whether the pointer is over this row.
    @State private var isHovered = false

    /// Builds the video row and its hover and context menu actions.
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSet) {
                HStack(spacing: 10) {
                    VideoThumbnail(image: image)
                        .frame(width: 72, height: 45)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .help(video.name)
                        Text(Duration.seconds(video.duration), format: .time(pattern: .minuteSecond))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 4)
                }
                .padding(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .help("Set as wallpaper")
            .accessibilityLabel(Text("Set \(video.name) as wallpaper"))
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Menu {
                Button("Rename…", action: onRename)
                Button("Remove from Library…", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 22, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .padding(.trailing, 8)
            .foregroundStyle(.secondary)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .disabled(isBusy)
            .help("Video actions")
            .accessibilityLabel(Text("Actions for \(video.name)"))
        }
        .liquidGlassEffect(in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor.opacity(isSelected ? 1 : 0), lineWidth: 2)
                .allowsHitTesting(false)
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Set as Wallpaper", action: onSet).disabled(isBusy)
            Button("Rename…", action: onRename).disabled(isBusy)
            Button("Remove from Library…", role: .destructive, action: onRemove).disabled(isBusy)
        }
    }
}

/// Edits a video's display title while preserving its file and identity.
private struct RenameVideoOverlay: View {
    /// The title being edited.
    @State private var title: String
    /// The selected portion of the title, initially the entire name.
    @State private var selection: TextSelection?
    /// Whether the title field has keyboard focus.
    @FocusState private var isTitleFocused: Bool
    /// Any failure encountered while saving the title.
    let error: String?
    /// Whether the library is performing another operation.
    let isBusy: Bool
    /// Saves the edited title.
    let onSave: (String) -> Void
    /// Dismisses the dialog without saving.
    let onCancel: () -> Void

    init(name: String, error: String?, isBusy: Bool, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _title = State(initialValue: name)
        self.error = error
        self.isBusy = isBusy
        self.onSave = onSave
        self.onCancel = onCancel
    }

    /// Builds the title field and keyboard-accessible dialog actions.
    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename Video").font(.headline)
                TextField("Title", text: $title, selection: $selection)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTitleFocused)
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                        .liquidGlassButtonStyle()
                    Button("Save") { onSave(title) }
                        .keyboardShortcut(.defaultAction)
                        .liquidGlassButtonStyle(isProminent: true)
                        .disabled(isBusy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .liquidGlassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
            .padding(28)
        }
        .onAppear {
            isTitleFocused = true
            selection = TextSelection(range: title.startIndex ..< title.endIndex)
        }
    }
}

/// Shows a video thumbnail or a placeholder.
private struct VideoThumbnail: View {
    /// The thumbnail image, when available.
    let image: NSImage?

    /// Builds the thumbnail image or film placeholder.
    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
            if let image {
                GeometryReader { geometry in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            } else {
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Shows the video count and quit button.
private struct LibraryFooter: View {
    /// The number of imported videos.
    let count: Int

    /// Builds the video count and quit control.
    var body: some View {
        HStack {
            Text("\(count) videos")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .padding(14)
    }
}

/// Shows an error message with a dismiss button.
struct ErrorBanner: View {
    /// The error message to display.
    let message: String
    /// Dismisses the displayed error.
    let onDismiss: () -> Void

    /// Builds the error message and dismiss control.
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(12)
        .liquidGlassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

/// Asks for confirmation before removing a library video.
private struct RemoveVideoOverlay: View {
    /// The video name shown to the user.
    let name: String
    /// Requests removal of this video.
    let onRemove: () -> Void
    /// Cancels the removal request.
    let onCancel: () -> Void

    /// Builds the removal confirmation dialog.
    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
            VStack(alignment: .leading, spacing: 16) {
                Text("Remove video?").font(.headline)
                Text("Remove “\(name)” from your library? Only Loopmural’s copy is deleted. Your original video stays untouched.")
                    .font(.subheadline)
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                        .liquidGlassButtonStyle()
                    Button("Remove", role: .destructive, action: onRemove)
                        .liquidGlassButtonStyle(isProminent: true, tint: .red)
                }
            }
            .padding(24)
            .liquidGlassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
            .padding(28)
        }
    }
}
