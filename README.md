# Loopmural - macOS Menu Bar Video Wallpaper App

**Loopmural** is a lightweight, modern, and privacy-focused macOS status bar application that turns your MP4 or MOV videos into moving desktop wallpapers. Built with SwiftUI, SwiftData, AVFoundation, ServiceManagement, and Apple's Liquid Glass visual language.

![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![SwiftUI](https://img.shields.io/badge/SwiftUI-SwiftData-purple)
![Localization](https://img.shields.io/badge/Languages-English%20%7C%20Japanese-green)

---

## 🌟 Key Features

- 🖥️ **Menu Bar Integration**: Lives in the macOS status bar with a custom template icon and zero Dock clutter (`LSUIElement = true`).
- 🖱️ **Right-Click Context Menu**: Right-click or `Ctrl+Click` the status bar icon for **Settings** (`Cmd+,`) and **Quit Loopmural** (`Cmd+Q`). Settings opens with the app activated in the foreground.
- 🎬 **MP4 and MOV Video Library**: Import one or more playable MP4 or MOV files, browse thumbnails and durations, and set a video as your wallpaper. Repeated imports of the same source path, size, and modification date are skipped.
- 📁 **Space-Saving Video Links**: New videos link to their originals by default using persistent read-only file access. Enable **Copy Videos into Library** in Settings for independent copies. Existing imports stay as copies. SwiftData stores library metadata and thumbnails.
- 🔁 **Looping Video Wallpaper**: Continuously loops each video with AVFoundation. Audio is always muted.
- 🖥️ **Multiple Display Support**: Creates a separate player and desktop window for each connected display. Videos fill the screen with aspect-ratio-preserving cropping. Display changes rebuild the wallpaper windows.
- ⏯️ **Playback Controls**: Pause, resume, or stop the wallpaper from the popover. Stop clears the startup selection; Quit preserves it for next time.
- 💤 **Sleep-Aware Playback**: Pauses during display sleep, system sleep, and inactive user sessions without changing your saved pause preference.
- 🔄 **Restore Last Wallpaper**: Optionally restore the last selected video when the app opens. Enabled by default; paused wallpapers remain paused.
- 🎨 **Liquid Glass UI Styling**: Uses macOS 26+ Liquid Glass effects with material fallbacks on macOS 15.
- 🗑️ **Video Removal Confirmation**: Removes the library entry and any app-owned copy after confirmation. Linked originals remain untouched.
- 🚀 **Launch at Login**: Optional auto-launch when you sign in, using Apple's `SMAppService`. Settings displays registration errors and required macOS approval.
- 🔒 **Local & Private**: Video playback, library storage, and preferences stay on your Mac. No analytics, advertising, telemetry, or app-managed cloud synchronization.
- 🌐 **Multilingual Support**: English and Japanese translations using Apple's String Catalog (`Localizable.xcstrings`).

Loopmural must remain running to display moving wallpaper. It uses non-interactive windows behind desktop icons; it does not replace macOS's system wallpaper configuration or change the lock-screen wallpaper. Placement with Spaces, Mission Control, and Stage Manager can vary by macOS version.

### Where to Find Copied Videos

With **Copy Videos into Library** enabled, Loopmural stores new video copies in its sandboxed local library:

```text
~/Library/Containers/com.kinn.Loopmural/Data/Library/Application Support/Loopmural/Videos
```

Linked videos remain in their original locations and must stay accessible. If a linked file becomes unavailable, reconnect its drive or choose **Locate File…** from its menu. Settings shows the space used by owned video copies; **Clear Library…** removes all library entries and owned copies while preserving originals.

In Finder, press **Cmd + Shift + G**, paste the path above, and press **Return**. Copies use UUID filenames ending in `.mp4` or `.mov`, preserving the imported format. Your original videos remain untouched; removing a video from Loopmural deletes only its imported copy and library record.

---

## 📁 Project Structure

```text
Loopmural/
├── Loopmural/
│   ├── LoopmuralApp.swift                     # MenuBarExtra, Settings scene, and app lifecycle
│   ├── ContentView.swift                      # Video library, playback controls, and overlays
│   ├── LoopmuralSettingsView.swift            # Login and wallpaper restoration settings
│   ├── WallpaperLibrary.swift                 # Links, copies, persistence, thumbnails, and removal
│   ├── WallpaperVideo.swift                   # SwiftData video metadata model
│   ├── WallpaperEngine.swift                  # Desktop windows, looping players, and sleep handling
│   ├── LaunchAtLoginManager.swift             # ServiceManagement registration and status
│   ├── MenuBarExtraRightClickMonitor.swift    # Native status bar context menu
│   ├── LiquidGlassStyle.swift                 # Liquid Glass styling with material fallbacks
│   ├── LoopmuralIcon.swift                    # Header and menu bar template icons
│   ├── Localizable.xcstrings                  # English and Japanese translations
│   ├── Assets.xcassets/                       # Logo layers and accent color
│   └── AppIcon.icon/                          # Layered application icon
├── Loopmural.xcodeproj/
│   └── xcshareddata/xcschemes/                # Shared scheme for local and cloud builds
├── LoopmuralTests/                            # Unit test target
├── LoopmuralUITests/                          # UI test target
├── .github/
│   ├── workflows/release.yml                 # Version bump, production merge, tag, and release
│   └── scripts/bump_version.py               # App and test-target marketing version updates
├── Makefile                                  # SwiftFormat command (make lint)
├── AGENTS.md                                 # Repository development rules
├── PRIVACY_POLICY.md                         # Privacy policy (English)
├── PRIVACY_POLICY_JA.md                       # Privacy policy (Japanese)
├── LICENSE                                   # PolyForm Noncommercial License 1.0.0
└── README.md                                 # Project documentation
```

---

## 🛠️ Tech Stack & Architecture

See [tech.md](tech.md) for how the moving desktop works, including flowcharts for wallpaper transitions and smooth video looping.

- **Language**: Swift 5 language mode
- **UI Framework**: SwiftUI (macOS 15.0+)
- **Menu Bar Engine**: `MenuBarExtra` (`.window` style) with local `NSEvent` monitoring
- **Desktop Windows**: Borderless AppKit windows above the desktop background and below desktop icons, ignoring mouse input
- **Video Playback**: `AVQueuePlayer`, `AVPlayerLooper`, and `AVPlayerLayer`, with one player per display
- **Data Persistence**: SwiftData for metadata and thumbnails, security-scoped bookmarks or app-local video copies, and `UserDefaults` for selection and preferences
- **System Integration**: `SMAppService.mainApp` for login registration and `NSWorkspace` notifications for sleep and session changes
- **Design System**: Liquid Glass effects and button styles on macOS 26+, with material and button-style fallbacks
- **Localization**: String Catalog (`.xcstrings`) with English and Japanese translations

---

## 📥 Download

[![Download on the Mac App Store](https://developer.apple.com/app-store/marketing/guidelines/images/badge-download-on-the-mac-app-store.svg)](https://apps.apple.com/jp/app/loopmural/id6821934534)

Build Loopmural from source using the instructions below. Version tags and release notes are available on the [GitHub Releases page](https://github.com/jinyongnan810/Loopmural/releases).

The release workflow publishes tags and notes; it does not build or upload an app binary.

---

## 💻 Requirements & Building

### Prerequisites

- macOS 15.0 (Sequoia) or later to run the app
- Xcode 27 for the current project format and SDK
- A valid signing configuration for installation and distribution

### Building & Running

1. Clone the repository:

   ```bash
   git clone https://github.com/jinyongnan810/Loopmural.git
   cd Loopmural
   ```

2. Open `Loopmural.xcodeproj` in Xcode.
3. Select the **Loopmural** scheme and destination **My Mac**.
4. Press `Cmd + R` to build and run.
5. Click the Loopmural menu bar icon, then **+** to import MP4 or MOV files.
6. Click a video's play button to set it as wallpaper.
7. Open **Settings** from the header or context menu to configure startup behavior.

Install the signed app in **Applications** before enabling **Launch at Login** for everyday use. If approval is required, use **Open Login Items Settings** to complete it in macOS System Settings.

### Releases & Xcode Cloud

The manually triggered **Release** GitHub Actions workflow follows C2V's release flow: choose `patch`, `minor`, `major`, or `keep`; update marketing versions when needed; fast-forward `main` into `production`; and publish a tag with categorized release notes. `keep` deletes and recreates the latest release and tag.

For Xcode Cloud, the selected branch must contain the committed shared scheme at `Loopmural.xcodeproj/xcshareddata/xcschemes/Loopmural.xcscheme`. Archive with the **Loopmural** scheme. The app's App Store category is **Utilities**.

---

## 🎨 Code Formatting & Quality

Code formatting uses SwiftFormat. To lint and format all Swift files, run:

```bash
make lint
```

Follow [AGENTS.md](AGENTS.md): use Xcode MCP for build verification and project configuration, and do not run test suites unless requested.

---

## 🛡️ Privacy Policy

Loopmural stores file bookmarks, optional video copies, thumbnails, library metadata, and preferences locally on your Mac. It does not upload your videos or include tracking or analytics. See the [Privacy Policy (English)](PRIVACY_POLICY.md) or [プライバシーポリシー (日本語)](PRIVACY_POLICY_JA.md) for details.

---

## 📄 License

Loopmural is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE).

You may use, copy, modify, and redistribute the software for noncommercial purposes under the license terms. When redistributing, include the license text or its URL and the required copyright notice. Commercial use requires separate permission from the copyright holder. See [LICENSE](LICENSE) for the full terms, including the permissions for noncommercial organizations.

The repository license does not restrict the copyright holder's own distribution of Loopmural. Third-party components, if any, remain subject to their own licenses.
