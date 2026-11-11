# Screenshots Timelapse

A small macOS menu bar app that takes a screenshot on a timer and exports each day as a timelapse video.

Screenshots Timelapse is an independent project. It is not affiliated with or endorsed by any other screenshot or timelapse app.

## Features

- Captures the screen every N seconds (default 30), with optional capture on start
- Block or allow specific apps so they never appear in frames
- Optionally show or hide the wallpaper, desktop icons and notifications
- Pauses when the screen is locked, the Mac is idle, or disk space is low
- Global start/stop shortcut
- Exports a day (or each display) to an H.264 `.mp4`
- Automatic cleanup of old day folders (move to Trash or delete)
- Runs from the menu bar only, with no Dock icon

## Requirements

- macOS 14 (Sonoma) or later
- Screen Recording permission (macOS asks on first capture)
- `ffmpeg` for video export: `brew install ffmpeg`

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
git clone https://github.com/neverstopdatta/Daylapse.git
cd Daylapse
sh scripts/setup-signing.sh   # one time: creates a local code-signing certificate
sh scripts/build.sh           # builds build/Screenshots Timelapse.app and launches it
```

`setup-signing.sh` imports a self-signed certificate named "Daylapse Local Signing" into your login keychain. A stable signature keeps the Screen Recording permission from resetting on every rebuild. Review the script before running it.

## Where things are stored

- Screenshots: `~/Pictures/Screenshots Timelapse/YYYY-MM-DD/` (changeable in Settings)
- Exported videos: inside the screenshots folder, under `Exports/`
- Log: `~/Library/Logs/Screenshots Timelapse.log`

## License

[MIT](LICENSE)
