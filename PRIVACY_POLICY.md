# Privacy Policy for Loopmural

[English](PRIVACY_POLICY.md) | [日本語](PRIVACY_POLICY_JA.md)

**Effective Date:** October 12, 2026

**Loopmural** ("the App", "we", "us", or "our") is a macOS menu bar application that plays your MP4 videos as moving desktop wallpapers. This policy describes the information the App processes and stores, and the controls available to you.

---

## 1. No Remote Data Collection or Transmission

- **No Uploads or Remote Processing**: Loopmural does not upload, transmit, share, or sell your videos, thumbnails, library metadata, preferences, or usage information to us or third parties.
- **No Analytics or Advertising**: The App includes no analytics, advertising, tracking, or third-party telemetry frameworks.
- **Offline Operation**: Importing videos, generating thumbnails, and playing wallpapers happen on your Mac. The App does not make external network requests or provide app-managed cloud synchronization.
- **Separate Services**: macOS, the Mac App Store, cloud file providers, and backup services operate under their own settings and policies. Selecting a source file stored in a cloud provider may cause that provider to download it. These services are not operated by Loopmural.

---

## 2. Local Storage & Security

- **Video Copies**: When you import an MP4, Loopmural reads the selected file and stores a separate copy in its local Application Support directory under `Loopmural/Videos`. The original file is not modified.
- **Library Metadata**: SwiftData stores a video identifier, display name, imported-copy filename, import date, duration, and optional thumbnail image. To recognize duplicate imports, the App also stores a source identifier containing the original file path, file size, and modification timestamp.
- **Preferences**: The selected video identifier, pause preference, and wallpaper restoration preference are stored locally using `UserDefaults`.
- **App Sandbox**: The App uses the macOS App Sandbox and user-selected file access. Imported copies and the database remain in app-local storage. Loopmural does not add its own encryption layer; file protection also depends on your macOS account, device security, and backup configuration.

---

## 3. User Control & Data Retention

- **Import and Playback**: You choose which MP4s to import and play. Pause and Stop do not delete library files. Stop clears the saved wallpaper selection. Quit preserves it for the next launch.
- **Removal**: After confirmation, the App deletes the selected video's library record and attempts to delete its imported copy. It reports errors if removal fails. Your original MP4 is never deleted by Loopmural.
- **Retention**: Library copies and records remain until you remove them or delete the app's local data. Uninstalling the app alone may leave its data on your Mac.
- **Full Local Data Removal**: After quitting Loopmural, you can delete its sandbox container at `~/Library/Containers/com.kinn.Loopmural/` to remove app-local data and preferences. Disable Launch at Login before uninstalling if you enabled it.
- **Backups**: Deletion in the App does not erase copies in your backups, cloud file providers, or original source locations. Normal file and database deletion does not guarantee forensic erasure of previously stored data.

---

## 4. Launch at Login

- Loopmural offers optional **Launch at Login** using Apple's `ServiceManagement` framework (`SMAppService.mainApp`). macOS manages registration and any approval on your Mac.
- You can disable this setting in the App or manage it in macOS System Settings. Loopmural does not send your login-item preference to us.
- **Restore Last Wallpaper** is a separate setting, enabled by default, that reopens your saved selection when the App launches. A paused wallpaper remains paused.

---

## 5. Changes to This Privacy Policy

We may update this policy to reflect changes to the App's functionality or data handling. Updated versions will be published in this repository with a revised effective date.

---

## 6. Contact Us

For questions about this policy or Loopmural's privacy practices, open an issue on the [official GitHub repository](https://github.com/jinyongnan810/Loopmural/issues). Issues are public; avoid including private videos, sensitive filenames, or personal file paths. Information you choose to submit to GitHub is handled under GitHub's policies.
