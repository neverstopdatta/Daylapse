# How Screenshots Timelapse works

Notes for anyone working on the code: what it does and why. The README covers usage.

The app is **Screenshots Timelapse**, SSTL in code: target and executable `SSTL`, bundle ID `dev.local.sstl`, type names like `SSTLSettings`.

## Build and run

- `swift build` compiles only. `scripts/build.sh` builds release, assembles `build/Screenshots Timelapse.app` (binary, `Info.plist`, `AppIcon.icns`, `MenuBarIcon@2x.png`), signs it and relaunches it.
- `scripts/app-icon.sh` and `scripts/menubar-icon.sh` render an SVG (`render-svg.swift`, compiled on first use) into `Resources/` and rebuild. `scripts/release.sh` sets the version in `Info.plist`, builds with `NO_LAUNCH=1`, zips, tags and creates the GitHub release; it refuses to touch an existing tag and leaves "Latest" alone for versions lower than the newest tag, because `UpdateChecker` reads GitHub's latest release. `scripts/push.sh` commits and pushes.
- `scripts/setup-signing.sh` creates a self-signed "SSTL Local Signing" identity once. A stable signature means macOS keeps the Screen Recording permission across rebuilds, instead of asking again after each one.
- `Info.plist` sets `LSUIElement`, so the app has no Dock icon and lives in the menu bar. It needs macOS 14 or later.

## Files on disk

| What | Where |
|---|---|
| Settings | `~/Library/Application Support/Screenshots Timelapse/settings.json` (a `.bak` is kept if it fails to decode) |
| Log | `~/Library/Logs/Screenshots Timelapse.log` (`SSTLLog.write`) |
| Screenshots | `<root>/<project>/YYYY-MM-DD/SSTL_YYYY-MM-DD_HH-mm-ss[_d<displayKey>].jpg` (`.heic` or `.png` by setting) |
| Videos | `<root>/<project>/Exports/<day>.mp4` or `SSTL_<first>_to_<last>.mp4`, with `-d<id>` per display when there are several |

The default root is `~/Pictures/SSTL`.

## Source map (`Sources/SSTL`)

| File | Role |
|---|---|
| `main.swift` | `AppDelegate`: status item, menu, wiring between all the parts below, project submenu |
| `CaptureEngine.swift` | The countdown timer: start/stop, pause holding, interval changes, when to shoot |
| `Screenshotter.swift` | Takes one screenshot per display with ScreenCaptureKit and writes the image file |
| `AppRules.swift` | Block/allow lists, frontmost-app tracking, and building the `SCContentFilter` (what is hidden) |
| `SystemState.swift` | Other pause reasons: locked, asleep, idle, low disk |
| `Settings.swift` | `SSTLSettings` (the saved model) and `SettingsStore` (load/save, project list, folder watcher) |
| `Projects.swift` | Project = folder; add/rename/remove; name checks; the New Project prompt |
| `Storage.swift` | Paths, day naming, retention deletes, size |
| `Displays.swift` | Stable display keys, file-name suffix, display picker options |
| `Exporter.swift` | Lists days and writes videos with AVFoundation (`AVAssetWriter`) |
| `ToggleFeedback.swift` | Notification and system sound when the global shortcut starts or stops capture |
| `Hotkey.swift` | Global start/stop shortcut via Carbon `RegisterEventHotKey` |
| `ShortcutRecorder.swift` | Shortcut recording field and key name display |
| `SettingsWindow.swift` | Settings window (and `SettingsTab` selection, so the menu can open a given tab), Apps tab, Timelapse (export) tab |
| `SettingsTabs.swift` | General, Capture and Storage tabs, plus shared controls (`DurationField`, `IntField`, `RepeatButton`) |
| `Log.swift` | Appends timestamped lines to the log file |
| `UpdateChecker.swift` | Reads the latest GitHub release tag, compares versions and links to the release page (daily if enabled, or from Settings > General) |

## Capture loop

1. `CaptureEngine.start()` starts a 0.2 s timer in the run loop's common modes, so it keeps firing while the menu is open. It also begins a `ProcessInfo` activity so App Nap doesn't slow it down.
2. Each `tick()`:
   - asks `pauseReason()`, which is `SystemState` first and then `AppRules`. A reason *holds* the countdown (the remaining time is saved in `pausedRemaining`) and shows a status such as `⏸ Idle` or `⊘ Not allowed`.
   - also holds while the menu or a focused Settings window is open, if "pause when menu open" is on.
   - when the countdown reaches zero, calls `performCapture()` and schedules the next shot from the *scheduled* time, not from now, so the interval doesn't drift.
   - if the interval setting changes, shifts the pending shot by the difference.
3. Stop with "resume countdown" on keeps the time left for the next start. "Capture on start" takes a shot immediately, or as soon as the menu closes if it is holding.
4. The status string drives the menu bar: `○` = idle (shows the icon), `⏸`/`⊘` = SF Symbol, `● 12s` = countdown text.

## Taking a screenshot

`Screenshotter.captureAllDisplays`:
- Takes a snapshot of the settings, gets `SCShareableContent`, and filters to the main display if set.
- `AppRules.makeFilter` builds the filter per display. The tricky parts:
  - **Block mode** excludes the blocked apps, this app, and notifications (unless shown). Hiding desktop icons means excluding Finder while keeping its normal windows.
  - **Wallpaper off**: excluding the wallpaper app doesn't remove the wallpaper. Three windows must be hidden by window (wallpaper agent, Dock's "Wallpaper-…", ownerless "Desktop") so the background colour shows through.
  - **Allow mode** includes only the allowed apps (plus wallpaper/notifications if shown). With desktop icons on, it instead hides every other window, because including apps never captures the icons. If an allowed app isn't running, it skips.
- After capture, `frontmostStillAllowsCapture` throws the frame away if settings or the frontmost app changed during the shot.
- Writes a `.tmp` file and then renames it, so a half-written image never appears. Retina frames can be half size (`halfSizeOnRetina`), with quality from settings.

## Days

- A frame's day folder is its calendar date (`dayName(for:)`), so work past midnight lands in the next day's folder. There used to be a "New day starts at" setting; projects made it unnecessary, so it was removed.
- Only folders named exactly `YYYY-MM-DD` count as days. Retention, Delete All, size and export ignore everything else (`Exports/`, user files).

## Projects and the folder watcher

- **The disk is the source of truth.** Settings store only `rootPath` and `activeProject` (a folder name). The project list is `SettingsStore.projects`, the visible subfolders of the root.
- **Folders are created only when needed**: the first screenshot, Show in Finder / Open Screenshots Folder, or New Project. A project with no folder yet appears in the list only while it is active.
- `reconcileProjects` runs on every save and on every watcher event:
  - If the active folder disappeared (it was on disk before), a one-out/one-in swap is treated as a Finder rename and followed. Otherwise it falls back to `Default`, then the first project.
  - If the root itself is missing (renamed away, disk unmounted), the selection is kept.
- If the root is renamed or moved, the watcher reads its new path from the open folder (`fcntl F_GETPATH`) and updates `rootPath`. A move into the Trash is treated as a deletion, not followed.
- `watchRoot` is a `DispatchSource` on the root directory (write/rename/delete). If the root is missing, it watches the parent instead and starts over on any change there. `syncWithDisk()` also runs when the menu opens and when Settings comes forward, as a safety net.
- **Rename** moves the folder (case-only renames go through a temporary name). **Remove** trashes or deletes the folder (following "Delete permanently"). **Change (Location)** points at another folder and doesn't move data; it refuses a folder that holds day folders directly.
- Background code reads `Storage.folderPath` (the active project's path), which `SettingsStore` keeps in sync.

## Settings flow

- `SettingsStore.shared` (`@Observable`, main actor) holds the saved settings. `save()` reconciles projects, updates the static mirrors (`Storage.folderPath`), writes JSON atomically and restarts the watcher if the root changed.
- The Settings window edits a local `@State` copy and saves on every change. It also pulls in outside changes (menu actions, watcher), skipping its own echo via `lastSaved`.
- `SSTLSettings` decodes each key with a default, so older or newer settings files still load. The old `hide*` keys are read once and inverted into `show*`.

## Displays and frame names

- `CGDirectDisplayID` can change (new primary display, reconnect), so frames are named by a **display key**: 8 hex characters hashed from the display's UUID (`CGDisplayCreateUUIDFromDisplayID`). The built-in display has no suffix; every other display gets `_d<key>`. Switching the primary display therefore never mixes screens in one video.
- The Capture tab's Displays setting is `all`, `main` (whichever display is primary now) or a display key. A stored key whose display is unplugged captures nothing and shows as "Disconnected display".
- Format setting: `jpeg`, `heic` or `png` (`Screenshotter.imageType`). Quality applies to JPEG and HEIC. HEIC is offered only if ImageIO can write it.
- Older files used a numeric display ID after `_d` or `-d`; `Exporter.displayKey` still groups them.

## Export

- `Exporter.export(batches:fps:in:job:progress:)` runs on a background queue. Each batch (one day, or several combined) becomes one video per display key. `ExportJob` carries the Cancel flag; cancelling deletes the partial file.
- Frames are sorted by the timestamp in the file name. The **newest** frame sets the video size (rounded down to even); other sizes are scaled to fit and centred on black. H.264 is used, or HEVC when a side exceeds 4096 px (hardware H.264 limit).
- Each frame is decoded with ImageIO and drawn (colour-managed, sRGB) into a BGRA pixel buffer; AVAssetWriter converts and encodes on the hardware encoder. A batch of frames is decoded in parallel while the previous batch is appended. Output is tagged BT.709.
- Speed is set by the hardware encoder, not decoding: 1,000 Retina frames (2940×1912) take about 11 s, the same as ffmpeg's `h264_videotoolbox` did. Half-size frames are about 4× faster.
- Writing for network use leaves a `<video>.mp4.sb-…` scratch file; `removeScratch` deletes it.
- **GIF** (`exportFormat` = `gif`): ImageIO's GIF writer, frames shrunk to 720 px on the long side, at most `gifMaxFrames` (300) evenly spaced frames, because ImageIO holds every frame in memory until the file is finished (about 1.2 GB peak at 300). Same size rule and Cancel as video.
- All exporting happens in the Timelapse tab. The menu's "Export Timelapse…" only opens that tab.

## Start/stop feedback

`performToggle(viaShortcut:)` in `main.swift` calls `ToggleFeedback.announce` only for the global shortcut. Sounds are the `.aiff` files in `/System/Library/Sounds`; choosing one in General plays it. Notifications use `UNUserNotificationCenter` (permission is requested when the toggle is switched on; a delegate lets them show while the app is frontmost).

## Retention and safety

- An hourly timer (plus once at launch) deletes day folders older than N days in every project, to the Trash or permanently.
- "Minimum free space" pauses capture. Free space is checked once a minute on the nearest existing folder, so the check doesn't create folders.
