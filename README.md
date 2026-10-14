<p align="center">
  <img src="Resources/icon-readme.png" width="128" height="128" alt="TimeScreen icon">
</p>

<h1 align="center">TimeScreen</h1>

<p align="center">
  A searchable history of your screen for macOS, like Rewind but <b>without the AI</b>. Everything stays on your Mac.
</p>

<p align="center">
  <img src="Resources/screenshot-welcome.png" width="260" alt="Welcome window">
  <img src="Resources/screenshot-timeline.png" width="520" alt="Timeline">
</p>

> Largely AI-written (see [AI-DISCLOSURE.md](AI-DISCLOSURE.md)). Not affiliated with Rewind. The screenshots here use
> made-up data.

---

TimeScreen lives in the menu bar and takes a screenshot every few seconds. Press a shortcut and the whole screen turns into
a timeline you can scroll through, search and copy text from. It reads the text in each screenshot with Apple's on-device
text recognition, and there is no language model and no inferencing anywhere.

## Features

| | |
|---|---|
| **Capture** | Every display, every 2 to 60 seconds (5 by default), skipping frames where nothing changed. Stored as HEIC; screenshots older than a day are shrunk to save space |
| **Timeline** | A full-screen filmstrip you scrub by scrolling anywhere. A colored bar shows which app you were in all day, with its icon. Pick days from a calendar, filter by app, or type a time (`3:45pm`, `15:30`, `noon`) into **Jump to time** |
| **Search** | Search everything you've seen, filtered by date range or app. Matches are highlighted on the screenshot, and ↑ ↓ step through the results |
| **Copy text** | Drag a box over a screenshot and press ⌘C to copy the words in it, or copy all the text in the frame |
| **Privacy** | Password managers are never recorded. Screens showing a private browsing window are skipped. Optional **Touch ID or password lock** on the timeline. One click to never record an app |
| **Delete** | Delete the frame you're looking at, the last 5, 15 or 60 minutes (also from the menu bar), or a whole day |
| **Storage** | Keep history from 7 days to forever, with a size limit (20 GB by default) that deletes the oldest screenshots first |
| **Power** | Optionally pauses on battery power or in Low Power Mode, and always when less than 1 GB of disk space is free |
| **Updates** | Updates itself with [Sparkle](https://sparkle-project.org); updates are signed |

<p align="center">
  <img src="Resources/screenshot-search.png" width="780" alt="Searching for a word">
</p>

## Install

Download the zip from [Releases](https://github.com/thebitstick/TimeScreen/releases) and move **TimeScreen.app** into
Applications (or `~/Applications`). It isn't notarized, so on first launch Control-click it and choose **Open**. macOS 14 or
later. A welcome window walks you through allowing **Screen Recording**.

## Using it

| | |
|---|---|
| Open the timeline | **⌥⌘T** (changeable, or removable, in Settings ▸ Shortcuts), the menu bar icon, or hold **⌘⇧** and scroll |
| Move | Scroll anywhere, or **← →**. In search results, **↑ ↓** and **Return** |
| Close | **Esc** |
| Pause | Menu bar ▸ Pause Recording, or Pause For 15 minutes, 1 hour or 8 hours |

The menu bar icon shows the state: recording, paused, a private window or power setting is stopping capture, the disk is
almost full, or Screen Recording access is missing. While Settings or the Welcome window is open, TimeScreen also shows a Dock
icon, which macOS needs for it to bring those windows to the front.

## Privacy and safety

- **Nothing leaves your Mac.** The only network traffic is Sparkle checking GitHub for a new version, which you can turn off in
  Settings ▸ General.
- Screenshots and the search index are stored **unencrypted** in `~/Library/Application Support/TimeScreen`. Turn on FileVault
  to protect them at rest. The timeline lock only guards the timeline, not those files.
- TimeScreen never records its own windows, the timeline while it is open, a locked or sleeping Mac, or apps on the
  never-capture list (1Password, Keychain Access, Passwords and Bitwarden by default).
- Private windows are recognized by title words (Incognito, InPrivate, Private Browsing, Private Window), which you can edit.
  **Safari doesn't mark private windows in their titles, so they can't be detected.** Add Safari to the never-capture list or
  use Pause For before browsing privately there.
- If something private did get recorded, delete it from the trash menu in the timeline or from **Delete Recent** in the menu bar.

## Troubleshooting

- **Nothing is being captured / the icon shows a triangle:** turn TimeScreen on in System Settings ▸ Privacy & Security ▸
  Screen & System Audio Recording, then quit and reopen it. macOS asks again after an update, because releases are signed
  ad hoc rather than with a developer certificate.
- **The timeline doesn't open:** check the shortcut in Settings ▸ Shortcuts (another app may use it) and, if you turned on the
  timeline lock, that you can authenticate.
- **Settings opens behind other windows the second time:** macOS is stubborn about menu bar apps. Click its Dock icon.
- **Copy Text isn't shown:** the frame was captured with "Make screen text searchable" turned off.
- **History is using a lot of disk:** lower the retention or the size limit in Settings ▸ Storage.

## Building

Swift 5.9+ and macOS 14+.

```sh
Scripts/dev.sh              # quit, rebuild, install into ~/Applications and launch
Scripts/build-app.sh        # build/TimeScreen.app only
swift test
```

Local builds are signed with the first "Apple Development" identity in your keychain, which lets macOS keep the Screen Recording
permission between rebuilds. `Scripts/make-demo-data.sh` writes a fictional day of screenshots for trying the timeline or taking
screenshots without real data. `AGENTS.md` has the release steps and design notes.

## License

MIT ([LICENSE.md](LICENSE.md)). Sparkle's license is in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
