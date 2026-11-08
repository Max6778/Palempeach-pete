#!/usr/bin/env bash
# Finds the file to analyze (from the repo or from the big-samples release)
set -e
T="$TARGET_INPUT"
case "$T" in
  release:*)
    NAME="${T#release:}"
    mkdir -p samples
    gh release download big-samples -p "$NAME" -D samples --clobber
    echo "TARGET=samples/$NAME" >> "$GITHUB_ENV" ;;
  *)
    echo "TARGET=$T" >> "$GITHUB_ENV" ;;
esac
