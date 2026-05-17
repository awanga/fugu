# Fugu

[![Build](https://github.com/awanga/fugu/actions/workflows/macos-ci.yml/badge.svg)](https://github.com/awanga/fugu/actions/workflows/macos-ci.yml)

Fugu is a lightweight, native macOS SFTP client with a dual-pane interface. Browse local and remote filesystems side by side, and transfer files by dragging and dropping between panes.

This repository is a community modernization of the original Fugu application developed by the University of Michigan RSCS group. **This effort is not affiliated with or endorsed by the original authors.** The goal is to make Fugu build and run reliably on current macOS while preserving the original lightweight, native character of the app.

---

## Features

- Dual-pane browser: local filesystem on the left, remote SFTP server on the right
- Connect using system OpenSSH — no bundled SSH library
- Password and public-key authentication; SSH agent passthrough
- Keychain integration for saved credentials
- Upload, download, create directory, delete, rename, and refresh
- Drag-and-drop transfers between panes
- Remote file preview and external-editor workflow
- Filenames with spaces, Unicode, leading dashes, and unusual characters handled correctly
- macOS 11 Big Sur and later; universal binary (Apple Silicon + Intel)

---

## Requirements

- macOS 11.0 or later
- Xcode 15 or later (to build from source)

---

## Building from source

```sh
# Debug build (no code signing required)
xcodebuild \
  -project Fugu.xcodeproj \
  -scheme Fugu \
  -configuration Development \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  clean build

# Static analysis
xcodebuild \
  -project Fugu.xcodeproj \
  -scheme Fugu \
  -configuration Development \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  analyze
```

The compiled app lands in `build/Default/Fugu.app`.

---

## Project status

Version 2.0.0 represents the first fully modernized build of Fugu, produced by a community
maintainer rather than the original University of Michigan team.

**What has been done (v2.0.0):**

- Build system: Xcode project repaired; clean build on current Xcode/macOS SDK
- CI: GitHub Actions workflow on macOS 14; builds and analyzes every PR
- Deprecated APIs: all removed (AppKit, Foundation, NSAlert, NSOpenPanel, NSRunAlertPanel)
- Security: process launches use exec + argv arrays only (no shell); remote path injection fixed at all sftp command sites; per-session temp directories with `0700` permissions; password buffers zeroed after use; secrets never logged
- Thread model: NSConnection distributed objects removed from all threads; replaced with GCD serial queues
- Static analyzer: all critical findings fixed; zero warnings on touched code
- Listing parser: extracted, isolated, and covered with 22+ fixture tests including hostile filenames, Unicode, large files, and edge-case dates
- Keychain: migrated to modern SecItem APIs

**Upcoming (planned for v2.1.0):**

- Signed and notarized release artifact; packaged `.dmg` for direct download
- SCP window (code clean; needs wiring into main UI and end-to-end test)
- SSH tunnel panel (code clean; needs UI entry point)
- Recursive remote directory deletion with confirmation dialog
- Server bookmarks with username, port, and default directory fields
- Local favorites / quick-access shortcuts for the local file browser panel
- ssh-keygen and ssh-add GUI integration (ssh-agent passthrough already works)
- UX polish: window sizing, split-view behavior, drag-and-drop continuity verification

---

## License and credits

The original Fugu application was developed by the Regents of The University of Michigan.
See [`COPYRIGHT.txt`](COPYRIGHT.txt) for the original license terms and attribution requirements.

This modernization is an independent community fork. All original copyright notices are preserved.

---

## Contributing

- Keep pull requests small and focused.
- New code touching process launches, path handling, parsers, or credential storage must include tests or a documented audit note.
- Do not introduce third-party runtime dependencies without a short design note.
- Never commit credentials, signing identities, provisioning profiles, or private test host data.
