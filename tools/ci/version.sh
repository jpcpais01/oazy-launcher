#!/usr/bin/env bash
# Prints the version for the current commit: <major.minor from VERSION>.<commits on HEAD>.
# Monotonic on main, so every merge produces a newer release.
set -euo pipefail
cd "$(dirname "$0")/../.."
base=$(tr -d '[:space:]' < VERSION)
count=$(git rev-list --count HEAD)
echo "${base}.${count}"
