#!/data/data/com.termux/files/usr/bin/bash
# Hands-off decompile tool. The agent only says WHICH FILE and WHICH TOOL.
#
#   ./decompile.sh FILE [auto|jadx|ghidra|kuna|rizin|all] [--full]   start (runs in background)
#   ./decompile.sh result [JOB] [--full]                             get the result when finished
#   ./decompile.sh status                                            list jobs
#
# Everything else (upload, big files, workflow, cached tools, download) is automatic.
# STARTED is only printed after GitHub confirms a real run exists.
# If a token is needed, log in once with: gh auth login   (or export GH_TOKEN=...)
set -e
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; cd "$HERE"
mkdir -p jobs

state_set() { # key name value
  local f="jobs/$1.state"; touch "$f"
  { grep -v "^$2=" "$f" 2>/dev/null || true; echo "$2=$3"; } > "$f.t"; mv "$f.t" "$f"
}

finish() { # key : download the result of a finished run
  . "jobs/$1.state"
  rm -rf "$OUT"; mkdir -p "$OUT"
  if gh run download "$RUN" -n summary -D "$OUT" >/dev/null 2>&1; then
    if [ "$FULL" = 1 ]; then gh run download "$RUN" -n full -D "$OUT/full" >/dev/null 2>&1 || true; fi
    state_set "$1" STATE done
  else
    state_set "$1" STATE failed
  fi
}

upload_and_trigger() { # key file tool : upload, start the workflow, record the REAL run id
  local KEY="$1" FILE="$2" TOOL="$3"
  local SHA8 NAME SIZE TARGET RUN
  SHA8=$(sha256sum "$FILE" | cut -c1-8)
  NAME="${SHA8}_$(basename "$FILE" | tr ' ' '_')"
  SIZE=$(stat -c %s "$FILE")
  if [ "$SIZE" -gt 94371840 ]; then
    [ "$SIZE" -gt 2000000000 ] && { echo "Over 2 GB: too big for GitHub releases."; state_set "$KEY" STATE failed; return 1; }
    gh release view big-samples >/dev/null 2>&1 || gh release create big-samples --title big-samples --notes "Large files for decompile workflow" >/dev/null
    if gh release view big-samples --json assets --jq '.assets[].name' | grep -qx "$NAME"; then
      echo "Already uploaded."
    else
      echo "Uploading $((SIZE/1024/1024)) MB..."
      local TMP="${PREFIX:-/tmp}/tmp/$NAME"; mkdir -p "$(dirname "$TMP")"; ln -sf "$FILE" "$TMP"
      gh release upload big-samples "$TMP" --clobber
      rm -f "$TMP"
    fi
    TARGET="release:$NAME"
  else
    mkdir -p samples
    [ -f "samples/$NAME" ] || cp "$FILE" "samples/$NAME"
    git add samples >/dev/null
    git commit -qm "add $NAME" 2>/dev/null || true
    git push -q
    TARGET="samples/$NAME"
  fi
  local BEFORE; BEFORE=$(gh run list --workflow decompile.yml -L1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo 0)
  gh workflow run decompile.yml -f target="$TARGET" -f tool="$TOOL"
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 3
    RUN=$(gh run list --workflow decompile.yml -L1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo 0)
    [ -n "$RUN" ] && [ "$RUN" != "$BEFORE" ] && break
    RUN=""
  done
  if [ -z "$RUN" ]; then
    echo "ERROR: GitHub did not start a new run. Is the workflow file pushed to the repo?"
    state_set "$KEY" STATE failed; return 1
  fi
  state_set "$KEY" RUN "$RUN"
  state_set "$KEY" STATE running
  echo "GitHub run started: $RUN"
}

cmd_run() { # internal: detached upload for big files
  upload_and_trigger "$@"
}

cmd_start() {
  local FILE="$1"; shift || true
  local TOOL=auto FULL=0 a
  for a in "$@"; do case "$a" in --full) FULL=1 ;; *) TOOL="$a" ;; esac; done
  [ -f "$FILE" ] || { echo "ERROR: file not found: $FILE"; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not logged in. Ask the USER to run: gh auth login   (do not ask them to paste a token in chat)"; exit 1; }
  local SHA8 NAME KEY OUT
  SHA8=$(sha256sum "$FILE" | cut -c1-8)
  NAME="${SHA8}_$(basename "$FILE" | tr ' ' '_')"
  KEY="$NAME-$TOOL"; OUT="out/$KEY"
  if [ -f "$OUT/summary.md" ] && { [ "$FULL" = 0 ] || [ -d "$OUT/full" ]; }; then
    echo "CACHED: this file was already analyzed with this tool. No waiting needed."
    cat "$OUT/summary.md"; exit 0
  fi
  if [ -f "jobs/$KEY.state" ]; then
    . "jobs/$KEY.state"
    if [ "$STATE" = running ] && [ -n "${RUN:-}" ] && [ "$(gh run view "$RUN" --json status --jq .status 2>/dev/null)" != completed ]; then
      echo "ALREADY RUNNING on GitHub (run $RUN). STOP and wait for the user to say it is done."; exit 0
    fi
  fi
  rm -f "jobs/$KEY.state"
  state_set "$KEY" STATE uploading
  state_set "$KEY" OUT "$OUT"
  state_set "$KEY" FULL "$FULL"
  local SIZE; SIZE=$(stat -c %s "$FILE")
  if [ "$SIZE" -gt 94371840 ]; then
    # big file: upload may take minutes, so detach it (needs setsid: pkg install util-linux)
    if command -v setsid >/dev/null; then
      setsid -f bash "$HERE/decompile.sh" _run "$KEY" "$(readlink -f "$FILE")" "$TOOL" > "jobs/$KEY.log" 2>&1 < /dev/null
      sleep 4
      if ! pgrep -f "decompile.sh _run $KEY" >/dev/null && ! grep -q '^STATE=running' "jobs/$KEY.state"; then
        echo "ERROR: the background upload died right away. Log:"; cat "jobs/$KEY.log"; exit 1
      fi
      echo "STARTED: $KEY. Big file: uploading in the background, then GitHub runs it."
    else
      echo "No setsid found, uploading in the foreground (may take a while). Tip: pkg install util-linux"
      upload_and_trigger "$KEY" "$(readlink -f "$FILE")" "$TOOL" || exit 1
      echo "STARTED: $KEY (GitHub is running it)."
    fi
  else
    upload_and_trigger "$KEY" "$(readlink -f "$FILE")" "$TOOL" || exit 1
    echo "STARTED: $KEY (GitHub is running it)."
  fi
  echo "AGENT: STOP NOW. Do not poll, sleep, or check status. Reply to the user with ONE short sentence:"
  echo "  'Started. Tell me when it is finished.'"
  echo "When the user says it is done, run: ./decompile.sh result"
}

cmd_result() {
  local KEY="" FULLNOW=0 a
  for a in "$@"; do case "$a" in --full) FULLNOW=1 ;; *) KEY="$a" ;; esac; done
  [ -n "$KEY" ] || KEY=$(ls -t jobs/*.state 2>/dev/null | head -1 | sed 's|jobs/||;s|\.state$||')
  [ -n "$KEY" ] && [ -f "jobs/$KEY.state" ] || { echo "No jobs yet."; exit 1; }
  . "jobs/$KEY.state"
  if [ "$FULLNOW" = 1 ] && [ "$FULL" != 1 ]; then state_set "$KEY" FULL 1; [ "$STATE" = done ] && state_set "$KEY" STATE running && STATE=running; fi
  . "jobs/$KEY.state"
  if [ "$STATE" != done ] && [ -n "${RUN:-}" ]; then
    # background watcher may have been killed by Android: check GitHub directly
    if [ "$(gh run view "$RUN" --json status --jq .status 2>/dev/null)" = completed ]; then finish "$KEY"; . "jobs/$KEY.state"; fi
  fi
  if [ "$STATE" = uploading ] && ! pgrep -f "decompile.sh _run $KEY" >/dev/null; then
    state_set "$KEY" STATE failed; STATE=failed
  fi
  case "$STATE" in
    done) cat "$OUT/summary.md"; echo; echo "Saved in: $HERE/$OUT"
          [ -d "$OUT/full" ] && echo "Full output: $HERE/$OUT/full (search with grep, do not cat)" || echo "Need the full code? Run: ./decompile.sh result $KEY --full" ;;
    failed) echo "FAILED. Last log lines:"; tail -n 15 "jobs/$KEY.log" ;;
    *) echo "NOT FINISHED YET (state: $STATE). STOP. Tell the user to wait and message you when it is done. Do not poll." ;;
  esac
}

cmd_status() { for f in jobs/*.state; do [ -f "$f" ] || continue; echo "$(basename "$f" .state): $(grep ^STATE= "$f" | cut -d= -f2)"; done; }

case "${1:-}" in
  result) shift; cmd_result "$@" ;;
  status) cmd_status ;;
  _run) shift; cmd_run "$@" ;;
  ""|-h|--help) sed -n '2,10p' "$0" ;;
  *) cmd_start "$@" ;;
esac
