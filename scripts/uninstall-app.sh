#!/usr/bin/env bash
set -euo pipefail

# Giữ y hệt `install-app.sh` — cùng một bản cài. `LoginItemTests` ràng cả hai
# vào `ProgramArguments` của LaunchAgent.plist trong bundle.
DEST="/Applications/KuroTools.app"
# Xem chú thích trong install-app.sh: sau M2 không LaunchAgent nào của app
# được phép nằm trong ~/Library/LaunchAgents. Bản uninstall cũ chỉ biết tới
# `com.kuro.kurovitals.app` và bỏ sót cái trùng label với agent trong bundle.
LEGACY_LABELS="com.kuro.kurovitals.app com.kuro.kurotools.app"

# Login item do `SMAppService` đăng ký từ BÊN TRONG app, và chỉ chính app mới
# huỷ đăng ký được (`SMAppService.unregister()`) — script không có đường nào
# làm thay. Xoá bundle khi công tắc còn bật để lại một mục "không tìm thấy"
# nằm lì trong System Settings ▸ General ▸ Login Items.
echo "⚠ Tắt 'Chạy khi đăng nhập' trong Settings ▸ Chung TRƯỚC khi gỡ, nếu nó đang bật."

if pgrep -f "$DEST/Contents/MacOS/KuroTools" >/dev/null 2>&1; then
  # Thoát bằng AppleEvent, không phải SIGTERM: `applicationWillTerminate` là
  # nơi quạt được trả về Auto, và `pkill` bỏ qua đúng bước đó.
  osascript -e 'quit app "KuroTools"' >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -f "$DEST/Contents/MacOS/KuroTools" >/dev/null 2>&1 || break
    sleep 0.5
  done
fi

rm -rf "$DEST"

for label in $LEGACY_LABELS; do
  plist="$HOME/Library/LaunchAgents/$label.plist"
  [ -f "$plist" ] || continue
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  rm -f "$plist"
  echo "Đã gỡ LaunchAgent viết tay cũ ($label)."
done

echo "✓ Đã gỡ $DEST. Quạt trở lại Auto khi app thoát; helper root gỡ riêng bằng ./scripts/uninstall-helper.sh."
