# Changelog

All notable changes to this project are documented here.
The format is loosely based on [Keep a Changelog](https://keepachangelog.com/).

## [1.6.0]

### Added
- **Embed images and PDFs in notes.** Attach via the 📎 toolbar button, or just paste an
  image/copied file straight into the editor — it's copied into `notes/assets/` and rendered
  inline (images as figures, PDFs in an inline viewer with **Open · Reveal · Path** actions).
  Served to the WebView through a sandboxed `cherry://asset/` scheme handler.
- **Wiki-links between notes.** `[[Note Title]]` renders as a clickable chip; clicking a link
  to a note that doesn't exist offers to create it. A **Linked from** (backlinks) section
  appears under any note other notes point at. New `[[ ]]` toolbar button.
- **Copy Path / Copy File on clips.** File-ish clipboard items (images, videos, PDFs, files)
  get **Copy Path**, **Copy File** (the real document — paste it in Finder/Mail), **Open**
  and **Reveal** actions. PDFs are now their own clip category with a filter chip.
- **Satisfying, adaptive capture sound.** Copying plays a soft "Pop"; re-copying the *same*
  thing gets dimmer and dimmer, and something new resets to full volume. Toggle it from the
  menu-bar right-click menu; pick another sound with
  `defaults write com.hico.nasnotes captureSoundName Tink`. System notification banners
  (and their alert sound) are gone — feedback is the in-app toast.
- **Drafts survive.** Closing the popover (or the app) mid-edit no longer loses anything —
  the editor state is snapshotted and restored on the next open.
- **Pinned notes.** Pin/Unpin from the note footer (stored as `pinned: true` frontmatter);
  pinned notes sort first with a 📌.
- **Recency sort + timestamps.** Unpinned notes sort by last-edited; each row shows a
  relative time (2m / 3h / 5d).
- **Global hotkey ⌃⌥⌘C** toggles Cherry from anywhere. In-app: **⌘N** new note, **⌘F** search,
  **⌘S** save, **Esc** back.
- **Right-click menu on the 🍒** — New Note, Clipboard History, Capture Sound toggle,
  **Launch at Login** (macOS 13+), Quit.
- **Export note as PDF** from the note footer (full content, not just the visible part).
- **Word & character count** live in the editor's hint bar.

### Changed
- **Deleting a note moves it to the macOS Trash** (recoverable) instead of removing it outright.

### Fixed
- **Overlapping capture sounds.** Apps that write the pasteboard more than once per ⌘C
  (plain + rich flavors) triggered stacked sounds; plays are now coalesced within a short
  window and a new sound stops the previous one instead of overlapping its tail.

## [1.5.0]

### Added
- **Name your note when you create it.** The new-note editor now opens with a dedicated
  **Name** field (focused first) instead of guessing the filename from the first heading.
- **Markdown formatting toolbar.** Buttons for Heading, **Bold**, *Italic*, bulleted list,
  quote, inline code and links — so you can format without knowing Markdown. `⌘B` / `⌘I` also work.

### Fixed
- **Couldn't paste into a note (⌘V did nothing).** A menu-bar (accessory) app has no menu bar,
  so the standard editing shortcuts never reached the editor. Added a proper **Edit** menu
  (Cut/Copy/Paste/Select All/Undo/Redo).
- JS `confirm()` / `alert()` / `prompt()` now show native panels via a `WKUIDelegate` — the
  delete-note confirmation previously failed silently.

## [1.4.0]

### Changed
- **Rebranded to Cherry Note Taker.** The menu-bar item is now **🍒 Cherry**, the app bundle is
  `Cherry.app`, and the repository is `cherry-note-taker`. Internal identifiers
  (`com.hico.nasnotes`, the `nasnote://` scheme, `NAS_NOTES_DIR`) are unchanged for compatibility.
- Screenshots + demo GIF regenerated with the new branding.

## [1.3.0]

### Added
- Clipboard **de-duplication**: re-copying the same content no longer stacks — the existing card gains a
  **×N** counter and moves to the top (images de-duped by content hash).
- A rich README with **real UI screenshots** and a demo **GIF**, plus `Scripts/snapshot.swift` +
  `Scripts/screenshots.sh` to regenerate them from the actual UI.

## [1.2.0]

### Added
- Clipboard: more data types — **emails, errors/stack traces, colors (with swatch), IP addresses,
  phone numbers** — on top of links/code/paths/images/videos/files/text.
- Clipboard **search** field (matches preview, filename, path, language, type).
- Clipboard **favourites**: ★ any clip; a Favourites filter; favourites are protected from the history cap.
- **In-app toast** on copy-back ("Now copied · <type> · <preview>") in the app's own theme.
- Existing string clips are **re-classified on launch**, so items captured before a detector existed
  (e.g. emails, errors) get re-sorted into the right category.

## [1.1.0]

### Added
- **Clipboard history** — a background pasteboard watcher captures everything you copy into an
  on-disk store (`~/Library/Application Support/NASNotes/clips`). A new **Clipboard** view shows
  entries **grouped by date** and filterable by type: **Links, Code, Paths, Images, Videos, Files, Text**.
  - Code is **auto-classified by language** (swift, python, javascript, bash, json, sql, html, …).
  - File **paths are auto-detected** and labeled.
  - Images/photos are thumbnailed inline; files/videos show name + path.
  - Click an entry to **copy it back**; per-item delete and **Clear all**.
  - Password-manager clips marked concealed/transient are **ignored**; history is capped at 300 items.

## [1.0.0]
First public release.

### Added
- Menu-bar status-item app (`LSUIElement`) with a `WKWebView` popover.
- **All Notes** home screen listing every `.md` note with a title + preview.
- Read view with Markdown rendering (headings, code fences, lists, blockquotes, links, inline code).
- **Add / Edit / Delete** notes in-app; edits are written back to the Markdown files atomically.
- `nasnote://<name>` URL scheme; **per-note Spotlight launcher apps** built by `Scripts/make-launchers.sh`.
- **CherryTree** export (`.ctd`) and one-click **Copy** of a whole note.
- `Scripts/rebuild.sh` regenerates the CherryTree doc and prunes/rebuilds launchers after any change.
- Configurable notes store via `NAS_NOTES_DIR` (default `~/.rpidrive/notes`).
- Native macOS look with automatic light/dark support.

[1.0.0]: https://github.com/Majboor/cherry-note-taker/releases/tag/v1.0.0
