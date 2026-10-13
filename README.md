# TimeScreen

A native macOS menu bar app that keeps a searchable history of your screen, like Rewind.ai but without any AI
inferencing. Everything stays on your Mac.

> Largely AI-written (see [AI-DISCLOSURE.md](AI-DISCLOSURE.md)). Not affiliated with Rewind.

- Captures every display every few seconds (ScreenCaptureKit), skipping frames where nothing changed
- Reads on-screen text with Apple's on-device Vision OCR and indexes it with SQLite FTS5
- Full-screen timeline overlay (global shortcut, default ⌥⌘T, configurable in Settings): scroll anywhere or use ← / → to scrub a filmstrip of thumbnails, pick a day, search everything you've seen, limited by date range or app. Esc closes
- Records the app and window title of whatever is topmost on each display, and skips a screen showing a private browsing window (matched by title words you can edit)
- Pause for 15 minutes, 1 hour or 8 hours from the menu bar
- Pauses while the screen is off, the Mac sleeps or the session is locked; never records TimeScreen itself
- Command + Shift + scroll opens the timeline; filter by app, copy text out of any screenshot, and a picker for each display
- A colored activity bar showing which app you were in all day, a calendar for picking days, and match highlighting on the screenshot
- Excluded apps (password managers by default), retention (7 days to forever) and an optional size limit that deletes the oldest screenshots first, open at login

Data lives in `~/Library/Application Support/TimeScreen` (`frames/` HEIC screenshots and `index.sqlite`).

## Download
Releases are on the [releases page](https://github.com/thebitstick/TimeScreen/releases). The app is ad-hoc signed, not notarized: after unzipping, right-click it and choose Open the first time.

## Building
Requires macOS 14+ and Xcode / Swift 5.9+.

```sh
./Scripts/build-app.sh      # builds build/TimeScreen.app
open build/TimeScreen.app
swift test
```
On first launch grant **Screen Recording** in System Settings → Privacy & Security. The build is ad-hoc signed, so
macOS may ask again after a rebuild; set `SIGN_IDENTITY="Apple Development: …"` to keep the grant.

## Not (yet) included
Audio. Per-window capture.

## License

MIT, see [LICENSE.md](LICENSE.md).
