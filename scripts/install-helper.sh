#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=.build/release/kurovitals-helper
[ -f "$BIN" ] || { echo "Run scripts/build-release.sh first"; exit 1; }

sudo install -m 755 -o root -g wheel "$BIN" /usr/local/libexec/kurovitals-helper

PLIST=/Library/LaunchDaemons/com.kuro.kurovitals.helper.plist
sudo tee "$PLIST" >/dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.kuro.kurovitals.helper</string>
  <key>ProgramArguments</key>
  <array><string>/usr/local/libexec/kurovitals-helper</string></array>
  <key>KeepAlive</key><true/>
  <key>RunAtLoad</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardErrorPath</key><string>/var/log/kurovitals-helper.log</string>
</dict>
</plist>
EOF

sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"
sudo launchctl unload "$PLIST" 2>/dev/null || true
sudo launchctl load "$PLIST"
echo "Helper installed and loaded."
