#!/bin/bash
# Install Cherry (https://cherry.waleeds.world) on macOS.
#   curl -fsSL https://cherry.waleeds.world/install.sh | bash
# Downloads the signed DMG, checks its SHA-256 and Apple's notarization, copies Cherry.app
# into /Applications (or ~/Applications if that isn't writable), and opens it.
set -euo pipefail
BASE="${CHERRY_BASE:-https://cherry.waleeds.world}"
say(){ printf '\033[1;31m›\033[0m %s\n' "$*"; }
die(){ printf 'cherry install: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "Cherry runs on macOS only."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || die "Cherry needs macOS 14 (Sonoma) or newer; this Mac has $(sw_vers -productVersion)."

tmp="$(mktemp -d)"; mnt="$tmp/mnt"
cleanup(){ hdiutil detach -quiet "$mnt" >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT

say "Downloading Cherry"
curl -fsSL "$BASE/Cherry.dmg" -o "$tmp/Cherry.dmg"
want="$(curl -fsSL "$BASE/Cherry.dmg.sha256" | awk '{print $1}')"
got="$(shasum -a 256 "$tmp/Cherry.dmg" | awk '{print $1}')"
[ -n "$want" ] && [ "$want" = "$got" ] || die "checksum mismatch (expected $want, got $got). Nothing was installed."
say "Checksum OK"

hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mnt" "$tmp/Cherry.dmg"
spctl --assess --type execute "$mnt/Cherry.app" 2>/dev/null || die "Apple's Gatekeeper rejected the app. Nothing was installed."
say "Signed and notarized"

dest=/Applications
[ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
pkill -x Cherry 2>/dev/null || true
rm -rf "$dest/Cherry.app"
ditto "$mnt/Cherry.app" "$dest/Cherry.app"
open "$dest/Cherry.app"

notes="$(defaults read com.hico.nasnotes notesDir 2>/dev/null || true)"
if [ -z "$notes" ]; then
  if [ -d "$HOME/.rpidrive/notes" ]; then notes="$HOME/.rpidrive/notes"; else notes="$HOME/Documents/Cherry"; fi
fi
say "Installed $dest/Cherry.app"
echo "  Cherry is in your menu bar (the note icon). Shortcut: Control-Option-Command-C."
echo "  Your notes folder: $notes"
