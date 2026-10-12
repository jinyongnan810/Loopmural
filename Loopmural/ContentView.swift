import AppKit
import SwiftUI

#Preview("Menu Bar") {
    ContentView(library: .shared, login: LaunchAtLoginManager())
}

struct ContentView: View {
    let library: WallpaperLibrary
    let login: LaunchAtLoginManager

    var body: some View {
        VStack(spacing: 0) {
            LibraryHeader(isImporting: library.isImporting, isBusy: library.isBusy) {
                library.chooseFiles()
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NowPlayingView(library: library)
                    if let error = library.errorMessage {
                        ErrorBanner(message: error) { library.errorMessage = nil }
                    }
                    VideoLibraryView(library: library)
                }
                .padding(16)
            }
            Divider()
            LibraryFooter(count: library.videos.count)
        }
        .frame(width: 420, height: 580)
        .background(.regularMaterial)
        .overlay {
            if let video = library.pendingRemoval {
                RemoveVideoOverlay(name: video.name) {
                    library.remove(video)
                } onCancel: {
                    library.pendingRemoval = nil
                }
            }
        }
        .onAppear { login.refresh() }
    }
}

private struct LibraryHeader: View {
    let isImporting: Bool
    let isBusy: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.rectangle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
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
                    .frame(width: 24, height: 24)
            }
            .disabled(isBusy)
            .help("Import MP4 files")
            .accessibilityLabel("Import MP4 files")
        }
        .padding(16)
    }
}

private struct NowPlayingView: View {
    let library: WallpaperLibrary

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
                            .foregroundStyle(.mint)
                    }
                }
            }
            .font(.caption)

            if let video = library.selectedVideo {
                VideoThumbnail(image: library.thumbnails[video.id])
                    .frame(height: 136)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(video.name)
                    .font(.headline)
                    .lineLimit(1)
                    .help(video.name)
                HStack {
                    Text("Muted · Loops on all displays")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if library.engine.hasWallpaper {
                        Button {
                            library.togglePaused()
                        } label: {
                            Image(systemName: library.engine.isPaused ? "play.fill" : "pause.fill")
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
                    Text("Import an MP4, then set it as your wallpaper.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct VideoLibraryView: View {
    let library: WallpaperLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR VIDEOS").font(.caption).fontWeight(.semibold)
                Spacer()
                Text("\(library.videos.count)").font(.caption).monospacedDigit()
            }
            .foregroundStyle(.secondary)
            if library.videos.isEmpty {
                Button {
                    library.chooseFiles()
                } label: {
                    Label("Import MP4 Files…", systemImage: "plus.circle")
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
                            onSet: { Task { await library.apply(video) } },
                            onRemove: { library.pendingRemoval = video }
                        )
                    }
                }
            }
        }
    }
}

private struct VideoRow: View {
    let video: WallpaperVideo
    let image: NSImage?
    let isSelected: Bool
    let isBusy: Bool
    let onSet: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
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
            Button(action: onSet) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "play.circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .help("Set as wallpaper")
            .accessibilityLabel(Text("Set \(video.name) as wallpaper"))

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .disabled(isBusy)
            .help("Remove from library")
            .accessibilityLabel(Text("Remove \(video.name) from library"))
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Set as Wallpaper", action: onSet).disabled(isBusy)
            Button("Remove from Library…", role: .destructive, action: onRemove).disabled(isBusy)
        }
    }
}

private struct VideoThumbnail: View {
    let image: NSImage?

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

private struct LibraryFooter: View {
    let count: Int

    var body: some View {
        HStack {
            Text("\(count) videos")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
            })
            .help("Settings")
            .accessibilityLabel("Settings")
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .padding(14)
    }
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

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
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct RemoveVideoOverlay: View {
    let name: String
    let onRemove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
            VStack(alignment: .leading, spacing: 16) {
                Text("Remove video?").font(.headline)
                Text("Remove “\(name)” from your library? Only Loopmural’s copy is deleted. Your original MP4 stays untouched.")
                    .font(.subheadline)
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Remove", role: .destructive, action: onRemove)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(28)
        }
    }
}
