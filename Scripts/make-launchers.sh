#!/bin/bash
# Build one Spotlight-launchable app per note in $NAS_NOTES_DIR/*.md.
# Each app opens nasnote://<base>, telling the running "NAS Notes" hub to focus that note.
# Stale launchers (whose note was deleted) are pruned. Re-run after adding/removing notes.
set -e
NOTES="${NAS_NOTES_DIR:-$HOME/.rpidrive/notes}"
APPS="$HOME/Applications"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cap(){ printf '%s' "$1" | awk '{print toupper(substr($0,1,1)) substr($0,2)}'; }
xesc(){ printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

# prune launchers whose note no longer exists (matched by our bundle id)
for app in "$APPS"/*\ Handover.app; do
  [ -e "$app" ] || continue
  id=$(/usr/bin/defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null || true)
  case "$id" in
    com.hico.nasnote.*) base="${id#com.hico.nasnote.}";
      # Timestamped automation run logs stay searchable in CherryTree but get no Spotlight app.
      case "$base" in *-run-[0-9]*) rm -rf "$app"; echo "pruned run log: $(basename "$app")"; continue ;; esac
      if [ ! -f "$NOTES/$base.md" ] || head -20 "$NOTES/$base.md" | grep -qE '^parent:[[:space:]]'; then rm -rf "$app"; echo "pruned: $(basename "$app")"; fi ;;
  esac
done

built=0; kept=0
for md in "$NOTES"/*.md; do
  [ -e "$md" ] || continue
  base=$(basename "$md" .md)
  case "$base" in *-run-[0-9]*) continue ;; esac  # run logs live in the Runs tab, not Spotlight
  head -20 "$md" | grep -qE '^parent:[[:space:]]' && continue   # sub-notes are reached via the tree, no launcher
  title=$(grep -m1 '^# ' "$md" | sed 's/^# //' || true)
  [ -z "$title" ] && title="$base"
  disp="$(cap "$title") Handover"
  disp=$(printf '%s' "$disp" | tr '/:' '--')  # "/" in a title would nest the .app path; ":" is Finder's separator
  app="$APPS/$disp.app"
  xdisp=$(xesc "$disp")
  # Already built for this note under this name? Leave it alone — rebuilding + re-signing every
  # launcher on every save was the disk thrash behind the "glitchy while typing" feeling.
  if [ -x "$app/Contents/MacOS/launch" ] && grep -qF "nasnote://$base\"" "$app/Contents/MacOS/launch"; then
    kept=$((kept + 1)); continue
  fi
  built=$((built + 1))
  rm -rf "$app"; mkdir -p "$app/Contents/MacOS"
  cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$xdisp</string>
  <key>CFBundleDisplayName</key><string>$xdisp</string>
  <key>CFBundleIdentifier</key><string>com.hico.nasnote.$base</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>launch</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict></plist>
EOF
  printf '#!/bin/bash\nopen "nasnote://%s"\n' "$base" > "$app/Contents/MacOS/launch"
  chmod +x "$app/Contents/MacOS/launch"
  codesign --force -s - "$app" >/dev/null 2>&1 || true
  "$LSREG" -f "$app" >/dev/null 2>&1 || true
  echo "built: $disp.app  ->  nasnote://$base"
done
[ "$built" -gt 0 ] && mdimport "$APPS" >/dev/null 2>&1 || true
echo "done. built $built, unchanged $kept."
