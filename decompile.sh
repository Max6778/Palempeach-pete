#!/data/data/com.termux/files/usr/bin/bash
# Usage: ./decompile.sh /path/to/file [auto|jadx|ghidra]
set -e
FILE="$1"; TOOL="${2:-auto}"
[ -f "$FILE" ] || { echo "File not found: $FILE"; exit 1; }
NAME=$(basename "$FILE")
cd "$(dirname "$0")"
mkdir -p samples
cp "$FILE" "samples/$NAME"
git add samples
git commit -m "add $NAME" || true
git push
gh workflow run decompile.yml -f target="samples/$NAME" -f tool="$TOOL"
sleep 10
RUN=$(gh run list --workflow decompile.yml -L1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --exit-status
rm -rf "out/$NAME"; mkdir -p "out/$NAME"
gh run download "$RUN" -D "out/$NAME"
echo "Done. Results are in: $(pwd)/out/$NAME"
