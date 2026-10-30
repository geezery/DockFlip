#!/bin/sh
# Prints the commit DockFlip is built from, for the version line in the menu bar menu:
# "c79a704", "c79a704-dirty" when the checkout holds code that commit does not, or
# "unknown" outside a git checkout. The Makefile puts it into Info.plist (DockFlipCommit).
# Tests: scripts/build-commit-tests.ps1.

cd "$(dirname "$0")/.." || { echo unknown; exit 0; }

commit=$(git rev-parse --short=7 HEAD 2>/dev/null) || { echo unknown; exit 0; }

# Dirty: a tracked file differs from HEAD (staged or not), or a new file sits where the
# build picks it up (SwiftPM compiles every file under Sources/, make app copies Resources/).
# Untracked files elsewhere (notes, logs) do not change the app, so they don't count.
if ! git diff --quiet HEAD -- 2>/dev/null \
   || [ -n "$(git ls-files --others --exclude-standard -- Sources Resources 2>/dev/null)" ]; then
    commit="$commit-dirty"
fi

echo "$commit"
