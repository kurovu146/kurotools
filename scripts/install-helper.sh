#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

# Script này chạy ở HAI nơi: trong repo (binary ở .build/release sau khi build)
# và trong gói tải về, nơi binary nằm ngay cạnh nó và không có mã nguồn nào cả.
# Bản trước chỉ biết đường dẫn repo, nên trong gói phát hành nó sẽ bảo người ta
# "chạy build-release.sh trước" — một script không tồn tại trên máy họ.
BIN=""
for candidate in "$HERE/kurovitals-helper" "$HERE/../.build/release/kurovitals-helper"; do
  if [ -f "$candidate" ]; then BIN="$candidate"; break; fi
done
if [ -z "$BIN" ]; then
  echo "Không tìm thấy kurovitals-helper — cạnh script này, hoặc trong .build/release"
  echo "sau khi chạy scripts/build-release.sh."
  exit 1
fi

# /usr/local/libexec doesn't exist by default on Apple Silicon — create it first.
sudo mkdir -p /usr/local/libexec
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

# Verify the daemon is up and answering on its socket.
sleep 1
if [ -S /var/run/kurovitals.sock ] && printf '{"ping":{}}\n' | nc -U /var/run/kurovitals.sock 2>/dev/null | grep -q pong; then
  echo "✓ Helper is running (ping → pong). Fan control ready."
else
  echo "⚠ Helper socket not responding yet. Check log: /var/log/kurovitals-helper.log"
fi
