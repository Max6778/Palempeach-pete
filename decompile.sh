#!/data/data/com.termux/files/usr/bin/bash
# Usage: ./decompile.sh /path/to/file [auto|jadx|ghidra|kuna|rizin|all]
# Files under 90 MB go through git. Bigger files (up to 2 GB) go through a
# GitHub Release named "big-samples" in your private repo.
set -e
FILE="$1"; TOOL="${2:-auto}"
[ -f "$FILE" ] || { echo "File not found: $FILE"; exit 1; }
NAME=$(basename "$FILE" | tr ' ' '_')
SIZE=$(stat -c %s "$FILE")
cd "$(dirname "$0")"

if [ "$SIZE" -gt 94371840 ]; then
  echo "Large file ($((SIZE/1024/1024)) MB): uploading as a release asset..."
  if [ "$SIZE" -gt 2000000000 ]; then echo "Over 2 GB: too big for GitHub releases."; exit 1; fi
  gh release view big-samples >/dev/null 2>&1 || gh release create big-samples --title "big-samples" --notes "Large files for decompile workflow"
  TMP="/data/data/com.termux/files/usr/tmp/$NAME"
  ln -sf "$(readlink -f "$FILE")" "$TMP"
  gh release upload big-samples "$TMP" --clobber
  rm -f "$TMP"
  TARGET="release:$NAME"
else
  mkdir -p samples
  cp "$FILE" "samples/$NAME"
  git add samples
  git commit -m "add $NAME" || true
  git push
  TARGET="samples/$NAME"
fi

gh workflow run decompile.yml -f target="$TARGET" -f tool="$TOOL"
sleep 10
RUN=$(gh run list --workflow decompile.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status || echo "Run reported a failure; downloading what exists..."
rm -rf "out/$NAME"; mkdir -p "out/$NAME"
gh run download "$RUN" -D "out/$NAME"
echo "Done. Results are in: $(pwd)/out/$NAME"
