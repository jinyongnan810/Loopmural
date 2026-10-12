# Loopmural

A local macOS menu bar app that plays MP4 videos behind desktop icons.

## Use

1. Open Loopmural.xcodeproj in Xcode and run the Loopmural scheme on My Mac.
2. Click the play-rectangle icon in the menu bar.
3. Click + to import one or more MP4 files.
4. Click a video's play button to set it as wallpaper on all connected displays.
5. Use the current wallpaper's pause/resume and stop buttons to control playback.
6. Open Settings with the gear button and enable Launch at Login to start automatically when signing in.

For normal use, install the signed app in Applications before enabling Launch at Login. If macOS requests approval, use the Open Login Items Settings button. Loopmural reads the actual SMAppService status and displays registration errors.

Restore Last Wallpaper is enabled by default. The selected video and pause preference survive relaunch. Stop clears the startup selection. Quit closes the desktop windows while preserving the selection for the next launch.

## Library

Imported MP4s are copied into the app's Application Support directory under Loopmural/Videos. SwiftData stores library metadata and thumbnails. Playback never depends on the original file remaining at its original location.

Import skips repeated selections of the same source path, size, and modification date. An updated source can be imported as a new entry. Unsupported, unreadable, or invalid videos produce an error in the popover.

Removing a video requires confirmation and removes only Loopmural's copy and library record. Original MP4 files are never deleted.

## Playback

- Borderless, non-interactive AppKit windows sit above the desktop background and below desktop icons.
- Each display has its own AVQueuePlayer, AVPlayerLooper, and AVPlayerLayer.
- Videos fill the screen with aspect-ratio-preserving cropping and always play muted.
- Display changes rebuild the windows. Display sleep, system sleep, and inactive user sessions suspend playback without changing the user's pause preference.
- The app must remain running. This does not install a system video wallpaper or change the lock screen.
- Spaces, Mission Control, and Stage Manager placement should be checked on each supported macOS release.

The implementation follows C2V's MenuBarExtra window scene, SwiftData persistence, accessory app mode, and ServiceManagement login registration. It keeps the deployment target and signing settings selected by the project creator.

## Development

Run make lint after Swift changes. Use Xcode MCP BuildProject for build verification. Do not run test suites unless requested, per AGENTS.md.

Main files:
- LoopmuralApp.swift: menu bar and settings scenes, application lifecycle.
- WallpaperVideo.swift: persistent video metadata.
- WallpaperLibrary.swift: import, storage, removal, and startup restoration.
- WallpaperEngine.swift: desktop windows, video looping, and sleep/display handling.
- ContentView.swift: menu bar library and playback controls.
- LaunchAtLoginManager.swift: SMAppService status and registration.
- LoopmuralSettingsView.swift: startup and playback settings.
