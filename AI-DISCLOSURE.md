# AI disclosure

This project was built with AI assistance.

## What the AI did

Almost all of the code and documentation in this repository was written by **Claude** (Anthropic; Claude
Sonnet 5.5, run through Claude Code) in a back-and-forth session with the project's author:

- All Swift sources, the unit tests, the build and icon scripts, and the documentation.
- The app icon, which is drawn in code by `Scripts/make-icon.swift`.
- Commits made with Claude's help carry a `Co-Authored-By: Claude` trailer.

TimeScreen itself uses machine learning, all of it on your Mac. Text is read from screenshots with Apple's Vision framework,
search is SQLite full-text search, and optional summaries are written by Apple's on-device language model (the Foundation Models
framework). The summaries are generated from recognized text only, nothing is sent anywhere, and the cloud model macOS 27 also
offers is deliberately not used.

## What the human did

The author decided what to build, set the direction (a Rewind-style timeline, first without AI and later with on-device summaries), chose the
features, and ran and used the app on their own Mac, reporting what worked and what did not.

## What was tested

- `swift test`: unit tests for the database and search, duplicate-frame detection, word boxes, compaction, the
  storage cap's database queries, search filters, window and private-title matching, the jump-to-time parser and
  the scroll gesture.
- On the author's Mac, and reported working by the author: capture, OCR and search with date and app filters,
  the full-screen timeline, scrolling anywhere, the global shortcut and Command+Shift+scroll, match highlighting,
  copying text, the app filter, the colored activity bar and calendar, the jump-to-time box, the settings window,
  pausing from the menu bar, the new timeline keys (⌘F, /, ⌥← ⌥→, ⇧← ⇧→, ⌘← ⌘→), the Text panel and the global Pause / Resume
  shortcut, the timeline lock (Touch ID or password), the delete menus and their confirmations, the
  menu bar icon's states, the one-click "never record this app" button and the ↑ ↓ keys in search results. Settings opening in front on every open was reproduced and checked by driving TimeScreen's menu with System Events.
- Checked by the AI against real data: compaction of frames older than a day, and that a private Zen window stops
  a screen being captured.
- The storage size limit, against real files in a temporary folder: it deletes the oldest frames, their search
  entries and empty day folders, and stops at 90% of the limit. That test found and fixed a bug where a small limit
  could delete every frame instead of stopping at the target.
- The first-run welcome window, on a throwaway copy with its own bundle identifier and data folder: it opens by
  itself on an empty history, shows the permission as not yet granted and no system prompt appears.
- Deleting history, on a copy of the author's real data in an isolated app instance: deleting the last hour removed
  every frame in that range together with its search entries, word positions and image files, and left the rest.
- The README screenshots use a fictional day of screenshots drawn by `Scripts/demo-data`, run through the app's real OCR.
  Searching and highlighting in them is the real code path.
- Export: the file writing (conversion between JPEG and HEIC, copying an unchanged file, a day's folder and transcript) is
  unit-tested, and the Save and folder panels with their format popup were seen opening above the timeline in a test copy.
  The author tried the earlier PNG version of export and reports it works.
- The development-build setting: with "install automatically" saved as on, a locally signed build reports automatic updates as
  off, and a release-style build does not get the flag.
- Orphan cleanup and the new keyboard navigation logic (previous and next app switch, the day the timeline opens on) are
  unit-tested; the orphan test caught a path-comparison bug that would have deleted indexed files. The Text panel was seen
  on fictional data, including restoring capitalization for frames stored with lowercase words.
- Starred moments: the rules that protect starred frames (retention, the size limit, compaction) are unit-tested, and the star
  button, badges and gold marks were seen on fictional data. The Star Moment shortcut and the starred list were not used.
- Summaries: the logic is unit-tested with a stub model (caching, rollups, progress, staleness, budgeting, retry, cleanup, deletion
  with the frames they cover). A live test runs Apple's real on-device model on fictional screens and was run by the AI; it skips
  itself where the model is unavailable. The AI also had the real model write a whole fictional day (34 blocks, 9 hours and the
  day) through the app's own code path.
- Updating: installed copies updated themselves through Sparkle four times (0.3.0 to 0.3.4) from signed releases.

## What was not tested

- The storage size limit on the author's own history, which has never come near the smallest limit (5 GB).
- Capturing more than one display: it was only run on a single-display Mac, so the display picker and multi-display
  capture are covered by unit tests alone.
- Pausing on battery power or in Low Power Mode, and pausing when the disk is almost full: the decisions are unit-tested and
  the battery reading was checked on a MacBook, but neither pause has been seen working in the app.
- Home and End in the timeline: the author's keyboard has neither key, so only ⌘← and ⌘→, which do the same, have been tried.
- The new Summary tab, the day recap popover and the Summaries settings on screen: the display was off when they were built, so
  they were not seen, and the automatic mode and the model on a Mac other than the author's have not been run. Summary quality
  is plausible but not guaranteed: it can mention things that are not on screen.
- Clicking through the export menu items and saving real files from them.
- Clicking through the welcome window on a clean install (Done, the permission button and the relaunch afterwards).
- Private browsing detection in Safari, which is not possible: Safari does not mark private windows in their
  titles. Other browsers are matched by title words and were only tried with Zen.
- macOS versions other than the author's, and any build other than the author's, including other signing
  identities.

## Caveats

- AI-written code can contain mistakes that look plausible. It has not had an independent human security
  audit. The app records everything on your screen, including whatever is visible when you forget to pause it.
  Screenshots and the OCR index are stored unencrypted in `~/Library/Application Support/TimeScreen`; protect
  them with FileVault, and add apps you never want recorded to the exclusion list.
- Please report problems as issues. Pull requests are welcome, AI-assisted or not; please say which.
