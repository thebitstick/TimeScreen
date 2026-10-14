# AI disclosure

This project was built with AI assistance.

## What the AI did

Almost all of the code and documentation in this repository was written by **Claude** (Anthropic; Claude
Sonnet 5.5, run through Claude Code) in a back-and-forth session with the project's author:

- All Swift sources, the unit tests, the build and icon scripts, and the documentation.
- The app icon, which is drawn in code by `Scripts/make-icon.swift`.
- Commits made with Claude's help carry a `Co-Authored-By: Claude` trailer.

TimeScreen is not an AI product: it contains no language model and performs no AI inferencing. Text is read from
screenshots with Apple's on-device Vision framework, and search is SQLite FTS5.

## What the human did

The author decided what to build, set the direction (a Rewind-style timeline without the AI), chose the
features, and ran and used the app on their own Mac, reporting what worked and what did not.

## What was tested

- `swift test`: unit tests for the database and search, duplicate-frame detection, word boxes, compaction, the
  storage cap's database queries, search filters, window and private-title matching, the jump-to-time parser and
  the scroll gesture.
- On the author's Mac, and reported working by the author: capture, OCR and search with date and app filters,
  the full-screen timeline, scrolling anywhere, the global shortcut and Command+Shift+scroll, match highlighting,
  copying text, the app filter, the colored activity bar and calendar, the jump-to-time box, the settings window,
  pausing from the menu bar, the timeline lock (Touch ID or password), the delete menus and their confirmations, and the
  menu bar icon's states. Settings opens in front on first open but can open behind other windows afterwards.
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
- Updating: installed copies updated themselves through Sparkle four times (0.3.0 to 0.3.4) from signed releases.

## What was not tested

- The storage size limit on the author's own history, which has never come near the smallest limit (5 GB).
- Capturing more than one display: it was only run on a single-display Mac, so the display picker and multi-display
  capture are covered by unit tests alone.
- Pausing on battery power or in Low Power Mode, and pausing when the disk is almost full: the decisions are unit-tested and
  the battery reading was checked on a MacBook, but neither pause has been seen working in the app.
- The one-click "never record this app" button and the ↑ ↓ keys in search results.
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
