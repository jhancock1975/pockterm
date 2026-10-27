#!/bin/bash
# Removes the TEMPORARY verify harness from pockterm.xcodeproj.
#
# Why this is a script rather than two git commands in a doc:
#   Package.resolved is TRACKED *inside* the .xcodeproj bundle, at
#   pockterm.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved.
#   So the obvious cleanup — `git checkout -- pockterm.xcodeproj` — also reverts
#   any dependency re-pin, silently, leaving no diff to notice afterwards. That
#   has already cost one SwiftTerm bump. This restores project.pbxproj alone and
#   then verifies Package.resolved came through byte-identical.
set -euo pipefail
cd "$(dirname "$0")/../../.."

PBX=pockterm.xcodeproj/project.pbxproj
BACKUP="$PBX.verifybak"
RESOLVED=pockterm.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
SCHEME=pockterm.xcodeproj/xcshareddata/xcschemes/pocktermUI.xcscheme

before=$(shasum "$RESOLVED" | awk '{print $1}')

if [[ -f "$BACKUP" ]]; then
    # Taken by add_uitest_target.rb before it touched the project, so this
    # restores whatever was there — including uncommitted project edits.
    mv "$BACKUP" "$PBX"
elif ! git diff --quiet -- "$PBX"; then
    echo "no $BACKUP; falling back to HEAD for project.pbxproj"
    git checkout -- "$PBX"
fi

rm -f "$SCHEME"
# Only if we emptied them; the app's own shared data must survive.
rmdir pockterm.xcodeproj/xcshareddata/xcschemes 2>/dev/null || true
rmdir pockterm.xcodeproj/xcshareddata 2>/dev/null || true

after=$(shasum "$RESOLVED" | awk '{print $1}')
if [[ "$before" != "$after" ]]; then
    echo "FAILED: Package.resolved changed during cleanup — restore it before committing"
    exit 1
fi

if grep -q pocktermUITests "$PBX"; then
    echo "FAILED: pocktermUITests is still in $PBX"
    exit 1
fi

echo "harness removed; Package.resolved intact"
git status --short pockterm.xcodeproj
