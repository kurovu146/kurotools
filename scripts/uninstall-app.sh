#!/usr/bin/env bash
set -euo pipefail
PLIST="$HOME/Library/LaunchAgents/com.kuro.kurovitals.app.plist"
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
pkill -f "/.build/release/KuroVitals" 2>/dev/null || true
echo "KuroVitals autostart removed and app stopped."
