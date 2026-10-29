#!/bin/zsh
# Runs the unit tests. With only the Command Line Tools installed, Swift Testing
# lives outside the default search paths, so point the build at it.
set -euo pipefail
cd "$(dirname "$0")/.."
# Fall back to the Command Line Tools if the Xcode license has not been accepted yet.
if ! swift --version >/dev/null 2>&1; then export DEVELOPER_DIR=/Library/Developer/CommandLineTools; fi
DEV="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [[ "$DEV" == *CommandLineTools* ]]; then
  F="$DEV/Library/Developer/Frameworks"; L="$DEV/Library/Developer/usr/lib"; PL="$DEV/usr/lib/swift/host/plugins/testing"
  exec swift test -Xswiftc -F"$F" -Xswiftc -plugin-path -Xswiftc "$PL" \
    -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
else
  exec swift test "$@"
fi
