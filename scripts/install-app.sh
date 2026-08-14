#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# See build-release.sh: `make rust` guards against linking a stale Rust
# staticlib that a bare `swift build` would silently reuse.
make rust
swift build -c release
BIN="$(pwd)/.build/release/KuroVitals"
PLIST="$HOME/Library/LaunchAgents/com.kuro.kurovitals.app.plist"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.kuro.kurovitals.app</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <!-- Restart only on crash (non-zero exit); a clean Quit from the menu stays quit. -->
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ThrottleInterval</key><integer>10</integer>
</dict>
</plist>
EOF
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
sleep 1
if pgrep -f "$BIN" >/dev/null; then
  echo "✓ KuroVitals is running in the background (and will start at login)."
  echo "  Quit from the menu bar to stop it; ./scripts/uninstall-app.sh to remove autostart."
else
  echo "⚠ KuroVitals didn't start. Run '$BIN' directly to see any error."
fi
