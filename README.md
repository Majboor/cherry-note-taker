<div align="center">

# 🍒 Cherry Note Taker

**A super-light macOS menu-bar notes app — with a built-in smart clipboard manager.**

Markdown notes, Spotlight launchers, CherryTree export, and a clipboard history that
auto-sorts everything you copy — in ~300 lines of dependency-free Swift.

![version](https://img.shields.io/badge/version-1.6.0-2563eb)
![platform](https://img.shields.io/badge/macOS-11%2B-lightgrey?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5-f05138?logo=swift&logoColor=white)
![license](https://img.shields.io/badge/license-MIT-22c55e)
![deps](https://img.shields.io/badge/dependencies-none-8b5cf6)

<br>

<img src="docs/img/demo.gif" width="440" alt="Cherry demo">

</div>

---

## ✨ What it does

- 🗂️ **Menu-bar notes** — an **All Notes** list; open any note to read rendered Markdown.
- ✍️ **Add / edit / delete in-app** — write Markdown, hit **Save**, it's a plain `.md` file.
- 🖼️ **Embed images & PDFs** — paste or 📎-attach; images render inline, PDFs get an in-note viewer.
- 🔗 **Wiki-links & backlinks** — `[[Note Title]]` jumps between notes; a **Linked from** section shows what points here.
- 📌 **Pinned notes, recency sort & drafts that survive** — close the popover mid-edit and pick up where you left off.
- 🔎 **Spotlight launchers** — every note gets its own app; ⌘-Space → type its name → jump straight to it. Or hit **⌃⌥⌘C** anywhere.
- 📋 **Clipboard history** — everything you copy, auto-sorted by **type** and **date**, with search & favourites; file clips get **Copy Path / Copy File / Open / Reveal**.
- 🔊 **Adaptive capture sound** — a soft pop on copy that fades when you re-copy the same thing and resets for new content.
- 🌳 **CherryTree export**, one-click **Copy**, and **Export as PDF**.
- 🪶 **No lock-in, no dependencies** — notes are just files in a folder you choose; pure AppKit + WebKit.

<br>

<div align="center">
<table>
  <tr>
    <td align="center"><img src="docs/img/home.png" width="250"><br><sub><b>All Notes</b></sub></td>
    <td align="center"><img src="docs/img/note.png" width="250"><br><sub><b>Read a note</b></sub></td>
    <td align="center"><img src="docs/img/clips.png" width="250"><br><sub><b>Clipboard history</b></sub></td>
  </tr>
</table>
</div>

---

## 📋 The clipboard manager

Everything you copy is captured into a local history and **auto-classified** — no tagging, no setup.

<div align="center">
<table>
  <tr>
    <td align="center"><img src="docs/img/search.png" width="270"><br><sub><b>Search + filter chips</b></sub></td>
    <td align="center"><img src="docs/img/toast.png" width="270"><br><sub><b>Click to copy back · in-app toast</b></sub></td>
  </tr>
</table>
</div>

| | |
|---|---|
| 🔗 **Links** · ✉️ **Emails** · 📞 **Phones** | detected from plain strings |
| 🎨 **Colors** (with a live swatch) · 🌐 **IPs** | `#3b82f6`, `192.168.1.24`, … |
| 💻 **Code** — *auto-labeled by language* | swift · python · js · bash · json · sql · html · … |
| 🐞 **Errors & stack traces** | `TypeError:`, `file.js:42`, tracebacks → their own category |
| 📁 **Paths** · 🖼️ **Images** · 🎞️ **Videos** · 📄 **Files** | thumbnails for images; name + path for files |

Plus:
- 🔁 **Copy the same thing twice?** It doesn't duplicate — the card shows a **×2 / ×3** counter and jumps to the top.
- 🔍 **Search** across preview text, filename, path, language and type.
- ⭐ **Favourites** — star the clips you reuse; they're kept even past the history cap.
- 🔒 **Privacy-aware** — password-manager clips (concealed/transient) are **ignored**; history is capped and local
  (`~/Library/Application Support/NASNotes/clips`). **Clear** anytime.

---

## 🚀 Install

Requirements: macOS 11+, Xcode command-line tools (`swiftc`). CherryTree optional (`brew install cherrytree`).

```bash
git clone https://github.com/Majboor/cherry-note-taker.git
cd cherry-note-taker
./Scripts/build.sh                # compiles + installs "~/Applications/Cherry.app"
./Scripts/install-login-item.sh   # (optional) start at login
```

Look for the **note icon** in your menu bar. `build.sh` seeds a sample note if your notes folder is empty.

---

## 🎯 Usage

| Action | How |
|--------|-----|
| Browse notes | Click the menu-bar item → **All Notes** |
| New note | **+** (top-right) |
| Edit / delete | Open a note → **Edit** → **Save** / **Delete note** |
| Copy a note | Note view → **Copy** |
| Open in CherryTree | Note view → **CherryTree** |
| Open the clipboard | **📋 Clipboard** (top-left of All Notes) |
| Copy an item back | Click it (a toast confirms) |
| Jump to a note from anywhere | ⌘-Space → type `"<Note> Handover"` |

Adding/removing notes auto-runs `Scripts/rebuild.sh` to refresh the CherryTree doc and Spotlight launchers.

---

## 🗄️ Notes store

Notes are `.md` files in the directory set by `NAS_NOTES_DIR` (default `~/.rpidrive/notes`). The first
`# Heading` line becomes the note's title. Back them up, grep them, or sync them however you like.

Adding notes programmatically (e.g. from a script or an AI agent) is just writing a `.md` file —
see **[docs/ADDING-NOTES.md](docs/ADDING-NOTES.md)** for the full handover.

## 🧱 Project layout

```
Sources/main.swift        # menu-bar app, popover, file I/O, nasnote:// URL scheme, bridge
Sources/html.swift        # the UI (HTML/CSS/JS) + Markdown renderer, as one inline template
Sources/clipboard.swift   # pasteboard watcher, classifier, on-disk clip store
Scripts/build.sh          # compile + bundle + install the .app
Scripts/install-login-item.sh
Scripts/make-launchers.sh # build/prune the per-note Spotlight apps
Scripts/rebuild.sh        # regenerate CherryTree doc + launchers
```

## 🗺️ Roadmap

See [ROADMAP.md](ROADMAP.md) — standalone editor window, note search, git-backed sync, global hotkey.
Work happens on `feature/*` branches. Changes are logged in [CHANGELOG.md](CHANGELOG.md).

## 📄 License

MIT — see [LICENSE](LICENSE).
