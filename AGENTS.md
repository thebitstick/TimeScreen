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
| `SettingsView.swift`, `Prefs.swift` | tabbed settings and the `UserDefaults` keys |
| `Tests/TimeScreenTests` | unit tests (database, signature, word boxes, compaction) |
| `WelcomeWindow.swift` | first-run window (shown only when the database is empty; `--welcome` forces it; `--timeline` opens the timeline at launch, for screenshots) |
| `Updater.swift` | Sparkle wrapper: update menu item, gentle reminders |
| `Scripts/build-app.sh` | builds and signs `build/TimeScreen.app` (there is no Xcode project) |
| `Scripts/publish-appcast.sh` | signs a release zip and uploads the Sparkle appcast |
| `Scripts/make-icon.swift` | draws `Resources/AppIcon.icns`; run from the repo root |

## Commands

```
swift test                       # unit tests
./Scripts/build-app.sh           # build/TimeScreen.app
SIGN_IDENTITY="Apple Development: ..." ./Scripts/build-app.sh   # keeps the Screen Recording grant across rebuilds
open build/TimeScreen.app
swift Scripts/make-icon.swift    # regenerate the icon, then iconutil (see the script)
```

- Check whether the app is already running with `pgrep -fl TimeScreen.app`; `pgrep -x` gives false negatives.
  Quit it before relaunching.
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
- **Storage cap:** `Recorder.enforceStorageCap` runs every 10 minutes, and when usage exceeds `maxStorageGB` it deletes
  the oldest frames (files, index and boxes) down to 90% of the cap. Retention by age is separate and hourly.
- Frames store the app's display name, not its bundle identifier, so icons are found by matching names against
  installed applications.

## Releasing

1. Set `CFBundleShortVersionString` **and** `CFBundleVersion` in `Resources/Info.plist` to the new version (Sparkle compares
   `CFBundleVersion`, so it must increase), commit, push.
2. `git tag -a vX.Y.Z -m ... && git push origin vX.Y.Z`: the `release` workflow tests, builds and attaches
   `TimeScreen-vX.Y.Z.zip`.
3. `Scripts/publish-appcast.sh vX.Y.Z` signs that zip with the Sparkle private key (login keychain, account
   `TimeScreen`; never export it or commit it) and uploads `appcast.xml` to the release. Use `--dry-run` to write
   `build/appcast.xml` without uploading. Without this step the app's feed (`releases/latest/download/appcast.xml`) 404s.
- Sparkle is embedded by `Scripts/build-app.sh`, which signs nested code first. The app needs the
  `disable-library-validation` entitlement (`Resources/TimeScreen.entitlements`) because release builds are ad-hoc signed.
- Updates re-prompt for Screen Recording whenever the signing identity differs between builds.

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
