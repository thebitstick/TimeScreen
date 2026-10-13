# TimeScreen

A native macOS menu bar app that keeps a searchable history of your screen, like Rewind.ai but without any AI
inferencing. Everything stays on your Mac.

> Largely AI-written (see [AI-DISCLOSURE.md](AI-DISCLOSURE.md)). Not affiliated with Rewind.

- Captures the main display every few seconds (ScreenCaptureKit), skipping frames where nothing changed
- Reads on-screen text with Apple's on-device Vision OCR and indexes it with SQLite FTS5
- Full-screen timeline overlay (global shortcut, default ⌥⌘T, configurable in Settings): scroll anywhere or use ← / → to scrub a filmstrip of thumbnails, pick a day, search everything you've seen. Esc closes
- Records the frontmost app and window title with each frame
- Pauses while the screen is off, the Mac sleeps or the session is locked; never records TimeScreen itself
- A colored activity bar showing which app you were in all day, a calendar for picking days, and match highlighting on the screenshot
- Excluded apps (password managers by default), retention (7 days to forever), open at login

Data lives in `~/Library/Application Support/TimeScreen` (`frames/` HEIC screenshots and `index.sqlite`).

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
Multiple displays (main display only), audio.

## License

MIT, see [LICENSE.md](LICENSE.md).
