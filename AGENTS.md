# CLAUDE.md

Guidance for Claude (or any contributor) working in this repository.

## What this is

A native macOS menu bar app (Swift, SwiftUI, SwiftPM) that keeps a searchable history of the screen, like
Rewind.ai without any AI inferencing: screenshots plus on-device OCR, nothing else. Everything stays on the
Mac. MIT licensed. The code is AI-written; keep `AI-DISCLOSURE.md` truthful when that changes.

Bundle identifier: `rip.bitstick.TimeScreen` (the author's namespace is `rip.bitstick.*`).

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/TimeScreen/TimeScreenApp.swift` | app entry, menu bar extra, Settings window scene |
| `Recorder.swift`, `Capturer.swift`, `Signature.swift`, `WindowInfo.swift` | capture loop, ScreenCaptureKit + Vision OCR, duplicate-frame detection |
| `Database.swift` | SQLite actor: frames, FTS5 index, word boxes |
| `TimelineController.swift` | full-screen overlay window, scroll and Esc monitors, Carbon global hotkey, shortcut recorder |
| `TimelineWindow.swift`, `ActivityBar.swift`, `AppIcons.swift` | timeline UI: preview, filmstrip, colored activity bar, calendar, app icons |
| `JumpTime.swift` | parses the timeline's jump-to-time box (ambiguous hours return both am and pm) |
| `HotKey.swift` | the global shortcuts and the recorder control in Settings |
| `Export.swift` | saving a frame as an image or text, and exporting a day or search results with a Markdown transcript |
| `SkipReason.swift` | why capture is skipped (private window, power, disk), plus the battery and free-space readings |
| `MenuBarState.swift` | which SF Symbol and description the menu bar icon shows |
| `Authenticator.swift` | the optional Touch ID / password lock on the timeline and its grace period |
| `SettingsView.swift`, `Prefs.swift` | tabbed settings and the `UserDefaults` keys |
| `Tests/TimeScreenTests` | unit tests (database, signature, word boxes, compaction) |
| `WelcomeWindow.swift` | first-run window (shown only when the database is empty; `--welcome` forces it; `--timeline` opens the timeline at launch, for screenshots; `-timelineDay yyyy-MM-dd` and `-timelineQuery text` preselect a day
  and a search) |
| `DockPresence.swift` | brings Settings, Welcome and update windows to the front (Dock presence while they are open) |
| `Updater.swift` | Sparkle wrapper: update menu item, gentle reminders |
| `Scripts/build-app.sh` | builds and signs `build/TimeScreen.app` (there is no Xcode project) |
| `Scripts/publish-appcast.sh` | signs a release zip and uploads the Sparkle appcast |
| `Scripts/make-demo-data.sh`, `Scripts/demo-data/` | draws a fictional day of screenshots, runs the real OCR and fills a data folder, for README screenshots |
| `Scripts/make-icon.swift` | draws `Resources/AppIcon.icns`; run from the repo root |

## Commands

Day to day, run `Scripts/dev.sh`: it quits the running app, rebuilds, installs into `~/Applications` and launches it.
Local builds are signed with the first "Apple Development" identity in the keychain (no name is stored in the repo), which
keeps the Screen Recording permission across rebuilds; ad-hoc builds (CI, releases, `SIGN_IDENTITY=-`) lose it every time.
A test copy with another bundle id or `TIMESCREEN_DATA_DIR` does not ask for the permission on launch.

```
swift test                       # unit tests
./Scripts/build-app.sh           # build/TimeScreen.app
SIGN_IDENTITY="Apple Development: ..." ./Scripts/build-app.sh   # keeps the Screen Recording grant across rebuilds
open build/TimeScreen.app
swift Scripts/make-icon.swift    # regenerate the icon, then iconutil (see the script)
```

- Check whether the app is already running with `pgrep -fl TimeScreen.app`; `pgrep -x` gives false negatives.
  Quit it before relaunching.
- `TIMESCREEN_DATA_DIR=/some/dir` points the app at a different data folder. A clean-install test also needs a different
  bundle identifier (copy the app, change `CFBundleIdentifier`, re-sign) so preferences and the Screen Recording grant start
  empty. Setting `HOME` does not move the data folder.
- `.build` records absolute paths: delete it after moving the repository.
- Changing the bundle identifier resets the app's preferences and its Screen Recording grant.

## Design decisions to preserve

- **Nothing leaves the Mac.** No network code, no analytics, no language model. OCR is Apple Vision on device.
- **Never record the app itself, the open timeline, excluded apps (password managers by default), a locked session, or a sleeping
  display.**
- **The overlay is a borderless `OverlayWindow`,** not a native full-screen window (that never went full screen).
  Scrolling anywhere works through a local scroll-wheel monitor that moves the filmstrip's clip view; the
  selected frame is derived from the scroll offset. `scrollPosition(id:)` does not track programmatic scrolls,
  so do not use it.
- **Esc is handled by a window-level key monitor,** because the search field swallows it otherwise.
- **Frames are deduplicated** with a 64x36 grayscale signature before OCR and storage.
- **Storage:** HEIC (JPEG fallback); frames older than a day are recompressed to 1728 px in the background.
  Word boxes are LZFSE-compressed JSON in the `boxes` table. Vision's origin is bottom-left; flip y when drawing.
- **Each display is attributed separately:** its frame takes the app and title of the topmost normal window
  centered on that display (`Windows.topWindow`), falling back to the frontmost app. Excluded apps, TimeScreen
  itself and private windows skip only that display. Private windows are detected by title keywords
  (`Prefs.privateTitles`), a heuristic: browsers word their private titles differently.
- **Timeline lock** (`Authenticator`, opt-in): every way of opening the timeline goes through `TimelineController.show()`, which
  asks `LAContext` (`.deviceOwnerAuthentication`, so a password works without Touch ID) when `requireAuth` is on and the grace
  period since the timeline last closed has passed. Sleep, screen lock and session switch end the grace period. It guards the
  timeline only; the screenshots on disk are plain files (FileVault is the answer there). Turning the lock on requires
  authenticating once, so a Mac with no password cannot lock itself out.
- **Windows come to the front through `DockPresence`.** An accessory app cannot reliably activate itself on recent macOS,
  so it switches to the regular (Dock) activation policy while a titled window is open and back afterwards. Settings opens
  through SwiftUI's `openSettings` (captured by a hook in the menu bar icon); `sendAction(showSettingsWindow:)` reports
  success but opens nothing. The menu item is a plain `Button` calling `DockPresence.openSettings()`: a `SettingsLink` in a
  menu is a native menu item, so gestures attached to it never run (that was the "opens behind on the second try" bug).
  To check window order for real, drive the menu with System Events: click `menu bar item 1 of menu bar 2` of the process, then
  the `Settings…` item, and compare `frontmost` and the window list before and after (needs Accessibility for the host app).
  `--settings` opens Settings at launch, for checking window order with `open -g`.
- **Deleting history** goes through `Recorder.delete(_:)` (index rows, boxes and search text first, then the files via
  `Storage.removeFiles`), from the timeline's trash menu and the menu bar's Delete Recent. Both confirm first.
- **The menu bar icon** comes from `MenuBarState` (permission, then paused, then private-window skip, then error).
- **Why capture stops** is one model, `SkipReason` (private window, battery power, Low Power Mode, disk almost full). It drives
  the menu status line and the menu bar icon (`MenuBarState`). Power and disk checks run before any window or capture work.
- **Never record this app** (the ⃠ button in the timeline) uses the frame's stored bundle identifier, falling back to
  `AppIcons.bundleIdentifier(for:)` for old frames, and the dialog says so if neither works.
- **Search results** navigate with ↑ ↓ from the search field (`moveResult`) and Return hands focus back to the timeline.
- **Export** (`Export.swift`): panels are presented as sheets on the overlay window, because the overlay sits above normal
  windows and would hide a free-standing panel. The image format is a popup in the panels' accessory view (`FormatAccessory`, remembered in
  `exportFormat`): Most Compatible is JPEG, High Efficiency is HEIC, Best Quality is PNG (lossless, but the stored frame is already HEIC, so it
  cannot restore detail), and a stored file already in the chosen format is copied
  without re-encoding (`ImageEncoding`). File work (`ImageEncoding`, `writeDay`) is `nonisolated` and runs off the main thread.
- **Hotkeys** (`HotKey.swift`): Carbon hot keys keyed by slot id (`timeline` = 1, `pause` = 2), each with its own pref keys, dispatched
  from one event handler. The pause shortcut is unset by default and plays Tink or Pop so you know which state you are in.
- **Orphan cleanup** (`Storage.removeOrphans`, at launch): files with no index row and older than a minute are deleted. It refuses
  to delete when the index is empty or when most files look orphaned, and it resolves symlinks before comparing paths (a
  `/var` versus `/private/var` mismatch made an early version delete indexed files).
- **Word case:** boxes now store words in their original case; older frames have lowercase boxes, so `WordBox.recased`
  restores case from the indexed text when a frame is loaded. The Text panel and Copy Text use the indexed text.
- **Memory:** the idle footprint is about 90 MB. The 270 MB it once showed was the filmstrip's thumbnail cache, which never shrank
  after the timeline closed; it is now capped at 64 MB by cost and emptied when the timeline closes (`Thumbnails.clear()`).
  Check with `footprint <pid>`; a large IOSurface line means images are being held.
- **Cadence:** captures slow to every 15 s after a minute without input and every 30 s after five (`CaptureCadence`), and the loop
  wakes early when you return. Settings ▸ Screen ▸ When away turns it off.
- **Search syntax** lives in `SearchQuery` (words are prefixes, `"phrases"` are exact, `-word` is `NOT`); the same parse feeds the
  FTS expression and the highlight terms, so excluded words are never highlighted. Odd input must never make a search throw.
- **Zoom** (`PreviewZoom`): the zoomed image is clipped to its unscaled frame; when zoomed a drag pans (using global coordinates, since
  the view moves under the finger) and ⇧-drag selects. `-previewZoom 2.5` sets it at launch.
- **Starred frames** (`frames.starred`) are skipped by `prune`, `oldestFrames` (so the size limit) and `framesToCompact`; only an
  explicit delete or Delete All removes them. The global Star Moment shortcut (slot 3) and the menu item star the newest frame, which
  is at most one capture interval old.
- **Storage cap:** `Recorder.enforceStorageCap` runs every 10 minutes, and when usage exceeds `maxStorageGB` it deletes
  the oldest frames (files, index and boxes) down to 90% of the cap. Retention by age is separate and hourly.
- Frames store both the app's display name and its bundle identifier (`bundle`; frames from before that column existed are
  backfilled at launch from what is known about the name). Icons and never-record resolve through the bundle identifier when
  there is one and fall back to matching the name against installed applications.

## Releasing

1. Set `CFBundleShortVersionString` **and** `CFBundleVersion` in `Resources/Info.plist` to the new version (Sparkle compares
   `CFBundleVersion`, so it must increase), commit, push.
2. `git tag -a vX.Y.Z -m ... && git push origin vX.Y.Z`: the `release` workflow tests, builds and attaches
   `TimeScreen-vX.Y.Z.zip`.
3. `Scripts/publish-appcast.sh vX.Y.Z` signs that zip with the Sparkle private key (login keychain, account
   `TimeScreen`; never export it or commit it) and uploads `appcast.xml` to the release. Use `--dry-run` to write
   `build/appcast.xml` without uploading. Without this step the app's feed (`releases/latest/download/appcast.xml`) 404s.
4. Replace the release's notes. The workflow only generates a list of commit titles, which hides what a feature is.
   Write the user-visible changes (what is new, what to know when upgrading) and run
   `gh release edit vX.Y.Z --notes-file <file>`. Keep the "Installing" section and the compare link. Notes live on the
   release; there is no `CHANGELOG.md`.
- Sparkle is embedded by `Scripts/build-app.sh`, which signs nested code first. The app needs the
  `disable-library-validation` entitlement (`Resources/TimeScreen.entitlements`) because release builds are ad-hoc signed.
- Builds signed with an "Apple Development" identity get `SUAllowsAutomaticUpdates=false` and `TimeScreenDevBuild=true` added to their
  built Info.plist (not the source one) by `build-app.sh`, so a dev copy is told about updates but never installs one itself.
  Release builds are ad-hoc and have neither key.
- Updates re-prompt for Screen Recording whenever the signing identity differs between builds, including when Sparkle
  replaces a locally signed copy with a release build.

## Working agreements

- **Ask before outward or irreversible actions:** pushing, committing in someone else's repo, deleting the
  user's captures, anything outside this repository. Approval for one does not carry to the next.
- **Never drive the user's keyboard or mouse.** Synthetic keystrokes once landed in another app's input box.
  Build and relaunch, then let the user try it, and say what was not verified on screen.
- **Never touch the user's uncommitted work.** Do not `git stash`, `reset` or `checkout` to compare things.
  Copy files aside instead.
- **Be honest about verification.** Say what was tested and what was not. Prefer a test that can fail over a claim.
- **No comments unless the code is not self-explanatory.** The author finds narrating comments a mark of
  AI-written code. Comment only a non-obvious *why* (a trap, a platform quirk), never what the code already says.
- **No `CHANGELOG.md` or `CONTRIBUTING.md`.**
- **Public repo hygiene:** no personal data (names, emails, signing identities, screenshots of real captures) in
  tracked files.
- **Clean up** scratch files and extra app instances you create, and say what you touched when asked.
- Commits made with Claude's help end with the `Co-Authored-By` trailer; the user is the author.

## README screenshots

Never use real captures. Generate a data folder with `Scripts/make-demo-data.sh /tmp/ts-demo 2026-10-13`, run a copy of the app
with its own bundle identifier and `TIMESCREEN_DATA_DIR=/tmp/ts-demo` (it then skips the permission prompt), open it with
`open -n --env TIMESCREEN_DATA_DIR=... TimeScreen.app --args --timeline -timelineDay 2026-10-13 [-timelineQuery git]`, and capture
with `screencapture` (`-l <window id>` for the Welcome window). Check each image for anything personal before committing it.
