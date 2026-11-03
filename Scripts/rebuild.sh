#!/bin/bash
# Regenerate everything derived from the note .md files: the CherryTree doc + the Spotlight launchers.
# Called by the NAS Notes app after a save/delete, and safe to run by hand.
NOTES="${NAS_NOTES_DIR:-$HOME/.rpidrive/notes}"
HERE="$(cd "$(dirname "$0")" && pwd)"
LOCK_DIR="$NOTES/.rebuild.lock"

# Several scheduled agents may finish together.  Launcher generation replaces
# shared .app bundles, so serialize the complete rebuild to prevent colliding
# rm/mkdir operations from leaving a partial bundle behind.
waited=0
until mkdir "$LOCK_DIR" 2>/dev/null; do
  if [ "$waited" -ge 60 ]; then
    echo "Timed out waiting for the NAS notes rebuild lock." >&2
    exit 1
  fi
  sleep 1
  waited=$((waited + 1))
done
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

# 1) CherryTree document (NAS.ctd) — NAS & email first (if present), then others alphabetically.
# Skipped on Macs without the developer tools: /usr/bin/python3 there is a stub that pops an install dialog.
if xcode-select -p >/dev/null 2>&1; then
NAS_NOTES_DIR="$NOTES" /usr/bin/python3 - <<'PY'
import xml.sax.saxutils as su, os, glob
nd=os.environ.get("NAS_NOTES_DIR") or os.path.expanduser("~/.rpidrive/notes")
pref=["NAS","email"]
bases=[os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(nd,"*.md"))]
order=[b for b in pref if b in bases]+sorted(b for b in bases if b not in pref)
nodes=[]
for i,name in enumerate(order,1):
    body=open(os.path.join(nd,f"{name}.md")).read()
    nodes.append(f'  <node name="{su.escape(name)}" unique_id="{i}" prog_lang="plain-text" tags="" '
                 f'readonly="0" nosearch_me="0" nosearch_ch="0" custom_icon_id="0" is_bold="1" foreground="">\n'
                 f'    <rich_text>{su.escape(body)}</rich_text>\n  </node>')
open(os.path.join(nd,"NAS.ctd"),"w").write(
    '<?xml version="1.0" encoding="UTF-8"?>\n<cherrytree>\n'+"\n".join(nodes)+'\n</cherrytree>\n')
PY
fi

# 2) Spotlight launcher apps (prune stale + rebuild current)
NAS_NOTES_DIR="$NOTES" "$HERE/make-launchers.sh" >/dev/null 2>&1
