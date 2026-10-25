#!/usr/bin/env bash
# Builds the player-facing release notes: every patch-notes/*.md entry added
# since the previous release tag, newest first. Usage: release_notes.sh <prev-tag|"">
set -euo pipefail
cd "$(dirname "$0")/../.."
prev="${1:-}"
if [[ -n "$prev" ]] && git rev-parse -q --verify "refs/tags/$prev" >/dev/null; then
  files=$(git diff --name-only --diff-filter=A "$prev" HEAD -- patch-notes/ | grep '\.md$' | grep -v README || true)
else
  files=$(ls patch-notes/*.md 2>/dev/null | grep -v README || true)
fi
if [[ -z "$files" ]]; then
  echo "- Behind-the-scenes improvements and fixes."
  exit 0
fi
first=1
for f in $(echo "$files" | sort -r); do
  [[ $first -eq 1 ]] || printf '\n'
  first=0
  cat "$f"
  printf '\n'
done
