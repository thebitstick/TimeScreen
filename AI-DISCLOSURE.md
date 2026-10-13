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

- `swift test`: unit tests for the database and search, duplicate-frame detection, word boxes and compaction.
- On the author's Mac: capture, OCR and search, the full-screen timeline overlay, scrolling anywhere, the global
  shortcut, and match highlighting.

## What was not tested

- The update flow end to end: the framework embeds, signs and launches, and the appcast and its signature generate
  from a real release, but no installed copy has yet updated itself to a newer release.
- Compaction of real captures older than a day (covered by unit tests only).
- Copying text from a screenshot and filtering by app: built and unit-tested, but not independently checked on screen.
- Capturing more than one display: it was only run on a single-display Mac, so the display picker and multi-display capture are covered by unit tests alone.
- macOS versions other than the author's.
- Any build other than the author's, including other signing identities.

## Caveats

- AI-written code can contain mistakes that look plausible. It has not had an independent human security
  audit. The app records everything on your screen, including whatever is visible when you forget to pause it.
  Screenshots and the OCR index are stored unencrypted in `~/Library/Application Support/TimeScreen`; protect
  them with FileVault, and add apps you never want recorded to the exclusion list.
- Please report problems as issues. Pull requests are welcome, AI-assisted or not; please say which.
