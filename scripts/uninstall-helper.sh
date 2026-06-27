#!/usr/bin/env bash
set -euo pipefail
PLIST=/Library/LaunchDaemons/com.kuro.kurovitals.helper.plist
sudo launchctl unload "$PLIST" 2>/dev/null || true
sudo rm -f "$PLIST" /usr/local/libexec/kurovitals-helper
sudo rm -f /var/run/kurovitals.sock
echo "Helper uninstalled. Fan returns to system Auto on next boot/SMC reset."
