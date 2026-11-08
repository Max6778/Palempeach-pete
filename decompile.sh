#!/data/data/com.termux/files/usr/bin/bash
# Hands-off decompile tool. The agent only says WHICH FILE and WHICH TOOL.
#
#   ./decompile.sh FILE [auto|jadx|ghidra|kuna|rizin|all] [--full]   start (runs in background)
#   ./decompile.sh result [JOB] [--full]                             get the result when finished
#   ./decompile.sh status                                            list jobs
#
# Everything else (upload, big files, workflow, cached tools, download) is automatic.
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

cmd_run() { # internal, runs in background: key file tool full
  local KEY="$1" FILE="$2" TOOL="$3" FULL="$4"
  command -v termux-wake-lock >/dev/null && termux-wake-lock || true
  local SHA8 NAME SIZE TARGET RUN
  SHA8=$(sha256sum "$FILE" | cut -c1-8)
  NAME="${SHA8}_$(basename "$FILE" | tr ' ' '_')"
  SIZE=$(stat -c %s "$FILE")
  if [ "$SIZE" -gt 94371840 ]; then
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
  state_set "$KEY" STATE running
  gh workflow run decompile.yml -f target="$TARGET" -f tool="$TOOL"
  sleep 8
  RUN=$(gh run list --workflow decompile.yml -L1 --json databaseId --jq '.[0].databaseId')
  state_set "$KEY" RUN "$RUN"
  gh run watch "$RUN" --exit-status >/dev/null 2>&1 || true
  finish "$KEY"
  command -v termux-notification >/dev/null && termux-notification --title "Decompile finished" --content "$KEY - tell the agent it is done" || true
  command -v termux-wake-unlock >/dev/null && termux-wake-unlock || true
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
  if [ -f "jobs/$KEY.state" ] && grep -qE '^STATE=(uploading|running)' "jobs/$KEY.state"; then
    echo "ALREADY RUNNING: $KEY. STOP and wait for the user to say it is done."; exit 0
  fi
  rm -f "jobs/$KEY.state"
  state_set "$KEY" STATE uploading
  state_set "$KEY" OUT "$OUT"
  state_set "$KEY" FULL "$FULL"
  nohup bash "$HERE/decompile.sh" _run "$KEY" "$(readlink -f "$FILE")" "$TOOL" "$FULL" > "jobs/$KEY.log" 2>&1 < /dev/null &
  disown 2>/dev/null || true
  echo "STARTED: $KEY (tool: $TOOL)"
  echo "It uploads to GitHub and runs in the background."
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
