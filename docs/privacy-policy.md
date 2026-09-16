# Knot Privacy Policy

Last updated: September 16, 2026

[简体中文](privacy-policy.zh.md)

Knot's core features run locally on your Mac. Knot requires no account and includes no advertising or analytics. It does not operate a personal-data collection service. Update checks and user-initiated website visits do involve network access, as described below.

## Data processed on your Mac

- Application names and local file metadata for search results.
- Clipboard text and images for clipboard history while Knot is running.
- Screen content when you start a screenshot or OCR command.
- Window information for window-management commands.
- Quicklinks, shortcuts, preferences, usage ranking, and capture metadata.

Clipboard history uses AES-GCM encryption with a key stored in macOS Keychain. OCR uses Apple's on-device Vision framework. Knot does not upload clipboard history, screenshots, or files as telemetry. Local app/file searches and OCR do not send their input to a server. A search Quicklink, by contrast, sends the query you explicitly submit to its destination website.

## Clipboard filtering and retention

The default settings retain 100 entries and apply a 30-day age limit to unpinned entries. Pinned entries are exempt from the age limit and can exceed the configured entry count; the encrypted archive still has a 128 MiB size budget. Settings allow changing the count, retention period, and excluded applications. Age-based cleanup runs when history policy is applied (for example, on startup, capture, or settings changes), not at an exact expiration deadline while idle.

Knot skips clipboard content marked concealed, transient, or auto-generated and excludes several password managers by default. These are **best-effort protections, not a guarantee that passwords or other secrets will never be recorded**. Not all apps mark sensitive content, and the source application is inferred from the frontmost app when Knot polls the clipboard. Switching apps quickly can cause incorrect attribution; an unknown source is not automatically excluded. Encryption protects the stored archive, not content shown in the app or copied back to the system clipboard.

## System permissions

- **Accessibility:** moving/resizing windows and directly pasting a selected history item into another application.
- **Screen Recording:** screenshots and OCR initiated by you.
- **Launch at Login:** optional and enabled only when you turn it on.

Manage Accessibility and Screen Recording in System Settings → Privacy & Security. Manage login items in System Settings → General → Login Items. These permissions do not authorize uploading screen or clipboard content.

## Storage and deletion

Knot is not App Sandbox-enabled; its data is not stored in an app container.

| Data | Location / behavior |
| --- | --- |
| Encrypted clipboard archive | `~/Library/Application Support/Knot/clipboard-history.bin` |
| Encrypted recovery copies | `clipboard-history-recovery-*.bin` in the same directory |
| Quicklinks, recovery copies, capture index | Other files in `~/Library/Application Support/Knot/`; these are not encrypted by Knot |
| Preferences and usage ranking | UserDefaults domain `app.baomi.knot` |
| Saved screenshots | The folder chosen in Capture settings; default `~/Pictures/Knot Captures` when saving is enabled; files are not encrypted by Knot |
| Clipboard encryption key | Keychain service `app.baomi.knot.clipboard.v2`, account `history-key` |

**Clear Clipboard History removes the active archive but deliberately preserves any recovery copies.** Recovery copies are created to protect unreadable data before replacement and have no automatic expiry. **Clear Capture History removes the index, not screenshot files.** Neither operation is a secure erase of disk blocks or external backups, and clearing history does not clear the current system clipboard.

To remove remaining local data:

1. Quit Knot so it cannot recreate files while you delete them.
2. In Finder, use Go → Go to Folder to open `~/Library/Application Support/Knot`. Delete the clipboard archive and recovery files to remove stored clipboard history, or delete the whole directory to also remove Quicklinks and the capture index.
3. Delete saved screenshots separately from the configured capture folder and any copies you exported elsewhere.
4. To reset all preferences and usage ranking, run `defaults delete app.baomi.knot` in Terminal while Knot is closed. This deletes settings, not screenshots or Keychain items.
5. If fully uninstalling, remove the matching Knot clipboard key from Keychain Access. Older development builds may have left a legacy `app.baomi.knot.clipboard` item. Removing keys makes archives encrypted with them unreadable; do not remove keys if you need to recover those archives.
6. Empty Trash when appropriate. Backups, synced folders, and the current system clipboard must be managed separately. Merely deleting Knot.app does not delete its user data.

## Network access

**Automatic update checks are enabled by default.** Sparkle checks GitHub Releases and downloads updates through GitHub and its download CDN. Those servers receive standard connection information, such as your IP address and HTTP request headers. Automatic downloads are disabled by default. You can change checks and downloads in Settings → General. Turning off automatic checks does not prevent network access when you manually check for or download updates.

Sparkle system profiling is disabled. Update requests do not include clipboard contents, screenshots, files, or search queries.

Quicklinks open the selected URL in its handler, typically your browser. Search Quicklinks include the query you choose to submit. External links, including help and privacy-policy links, visit their destination websites. Those services process requests under their own privacy policies.

## Changes and contact

Changes to this policy will be published with an updated date on baomi.app and in the Knot repository. For privacy questions, use the contact link at [baomi.app](https://baomi.app).
