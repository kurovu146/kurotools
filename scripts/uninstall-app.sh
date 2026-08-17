#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.kuro.kurovitals.app.plist"
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
# Anchored to THIS checkout's own $ROOT — a bare "/.build/release/KuroTools"
# substring would also match a process started from a different checkout or
# worktree of this repo.
pkill -f "$ROOT/.build/release/KuroTools" 2>/dev/null || true
echo "KuroTools autostart removed and app stopped."
