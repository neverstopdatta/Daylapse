# Screenshots Timelapse

A small macOS menu bar app that takes screenshots on a timer and exports them as a timelapse video.

Screenshots Timelapse is an independent project. It is not affiliated with or endorsed by any other screenshot or timelapse app.

## Features

- Captures the screen every N seconds, with optional capture on start
- Choose which display to capture (all, the main one, or a specific screen) and the image format (JPEG, HEIC or PNG)
- Block or allow specific apps so they never appear in frames
- Optionally show or hide the wallpaper, desktop icons and notifications
- Pauses when the screen is locked, the Mac is idle, or disk space is low
- Global start/stop shortcut, with an optional notification and sound (any macOS system sound) when you use it
- Projects: separate screenshot folders and day lists, switched from the menu bar
- Exports a day (or each display, or several days combined) to an `.mp4` or a GIF, with progress and Cancel. Video is written by macOS itself, so nothing extra needs installing
- Automatic cleanup of old day folders (move to Trash or delete)
- Runs from the menu bar only, with no Dock icon

## Requirements

- macOS 14 (Sonoma) or later
- Screen Recording permission (macOS asks on first capture)

## Download

Grab `Screenshots-Timelapse.zip` from the [Releases](../../releases) page and unzip it.

The app is signed with a self-made certificate, not an Apple Developer ID, so Gatekeeper will warn on first launch. To open it, right-click `Screenshots Timelapse.app` and choose **Open**, or run:

```sh
xattr -cr "/path/to/Screenshots Timelapse.app"
```

Then grant Screen Recording in System Settings > Privacy & Security.

## Build from source

You need Xcode or the Xcode Command Line Tools (Swift 5.10+). There are no third-party packages.

```sh
git clone https://github.com/neverstopdatta/Screenshots-Timelapse.git
cd Screenshots-Timelapse
sh scripts/setup-signing.sh   # one time: creates a local code-signing certificate
sh scripts/build.sh           # builds build/Screenshots Timelapse.app and launches it
```

`setup-signing.sh` imports a self-signed certificate named "SSTL Local Signing" into your login keychain. A stable signature keeps the Screen Recording permission from resetting on every rebuild. Review the script before running it.

Other scripts in `scripts/`:

- `app-icon.sh [icon.svg]` and `menubar-icon.sh [icon.svg]` turn an SVG into the icons (needs Xcode tools) and rebuild the app
- `push.sh "message"` commits and pushes
- `release.sh <version>` builds, tags and publishes a GitHub release with the zip attached (needs the `gh` CLI)

For how the code is organised and why, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Where things are stored

- Screenshots: `~/Pictures/SSTL/<Project>/YYYY-MM-DD/` as `.jpg`, `.heic` or `.png` (location changeable in Settings)
- Projects: each folder inside the location is a project, so renaming or deleting one in Finder updates the app. Renaming or moving the location folder itself is followed too
- Exported videos: inside each project folder, under `Exports/`
- Log: `~/Library/Logs/Screenshots Timelapse.log`

## Tips

- **GIFs** are written frame by frame, so even long clips use little memory. Choose the size, colours (256 looks best) and optional dithering in the Timelapse tab. Only the part of the screen that changed is stored for each frame, so mostly still recordings stay small.
- **Trim frames without an editor:** open a day folder in Finder, select the first frame and press Space for Quick Look. Use the arrow keys to step through frames, and press ⌘⌫ on any frame you don't want in the video. Export from the Timelapse tab afterwards.

## Updates

Settings > General shows the version and can check GitHub for a newer release, automatically once a day or on demand. The check only reads the latest release number from GitHub's API. Nothing is downloaded or installed; you get a link to the release page. Turn off "Check for updates automatically" to stop the request.

## License

Copyright (c) 2026 neverstopdatta. Licensed under the [GNU General Public License v3.0](LICENSE). You can use, modify and share it, but anyone who distributes a modified version must also release it under the GPL with its source.
