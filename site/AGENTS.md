# Installing Cherry (instructions for AI agents)

Cherry is a free, open-source (MIT) macOS menu-bar notes app with a clipboard history.
Source: https://github.com/Majboor/cherry-note-taker · Site: https://cherry.waleeds.world

## Requirements
- macOS 14 (Sonoma) or newer, Apple silicon or Intel. Check with `sw_vers -productVersion`.
- If the Mac is older, stop and tell the user. Do not try to build from source as a workaround.

## Install (pick one)
1. If `brew` is on the PATH:
   ```bash
   brew install --cask majboor/tap/cherry
   ```
2. Otherwise run the install script. It verifies the download's SHA-256 and Apple's
   notarization before installing, and installs nothing if either check fails:
   ```bash
   curl -fsSL https://cherry.waleeds.world/install.sh | bash
   ```
Do not use `sudo`. Do not disable Gatekeeper or remove quarantine attributes.

## Check it worked
```bash
pgrep -x Cherry && echo running
```
If it is not running: `open -a Cherry`.

## Tell the user
- Cherry lives in the menu bar (a note icon). Global shortcut: Control-Option-Command-C.
- Notes folder: `~/Documents/Cherry` on a new install. Read the actual value with
  `defaults read com.hico.nasnotes notesDir` (if unset, it is `~/Documents/Cherry`).

## Adding notes for the user
A note is a Markdown file in the notes folder. Cherry picks up new files on its own.
```markdown
---
category: General
tags: example, howto
---
# Note title

Body in Markdown.
```
- File name: lowercase-with-hyphens, `.md`. The first `# ` line is the title.
- Files named `*-run-<digits>.md` are treated as agent run logs and kept out of the main list.
- Never delete or rewrite notes you did not create unless the user asks.

## Uninstall
```bash
brew uninstall --cask cherry   # if installed with Homebrew
# or
pkill -x Cherry; rm -rf /Applications/Cherry.app ~/Applications/Cherry.app
```
The notes folder is left in place.
