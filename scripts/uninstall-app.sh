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
  echo "Đang thoát bản KuroTools đang chạy…"
  osascript -e 'quit app "KuroTools"' >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -f "$DEST/Contents/MacOS/KuroTools" >/dev/null 2>&1 || break
    sleep 0.5
  done
  # 🔑 CÙNG cổng từ chối như `install-app.sh`, và nó phải đứng trước CẢ HAI
  # thao tác phá huỷ bên dưới. `osascript` cần quyền Automation (Apple Events)
  # cho terminal đang gọi; bị từ chối thì `|| true` nuốt mất, và lần chạy đầu
  # trên một terminal mới rơi đúng vào đây. Chạy tiếp nghĩa là:
  #   1. `rm -rf` một bundle đang chạy — bản cài biến mất, không có gì thay thế;
  #   2. `launchctl bootout` cái label đã khởi động tiến trình đó — SIGTERM,
  #      KHÔNG chạy `applicationWillTerminate`, nên quạt kẹt nguyên RPM ép cuối
  #      cùng cho tới khi helper hết TTL.
  if pgrep -f "$DEST/Contents/MacOS/KuroTools" >/dev/null 2>&1; then
    echo "⚠ KuroTools vẫn đang chạy. Thoát nó từ menu bar rồi chạy lại script này." >&2
    exit 1
  fi
fi

rm -rf "$DEST"

for label in $LEGACY_LABELS; do
  plist="$HOME/Library/LaunchAgents/$label.plist"
  [ -f "$plist" ] || continue
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  rm -f "$plist"
  echo "Đã gỡ LaunchAgent viết tay cũ ($label)."
done

# Screensaver là một bundle RIÊNG, nằm ngoài KuroTools.app — gỡ app mà bỏ quên
# nó thì System Settings vẫn liệt kê một screensaver không còn ai nuôi, và bản
# copy video (có thể vài trăm MB) nằm lì trong container.
SAVER="$HOME/Library/Screen Savers/KuroToolsWallpaper.saver"
SAVER_VIDEO="$HOME/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/KuroTools"
if [ -d "$SAVER" ] || [ -d "$SAVER_VIDEO" ]; then
  pkill -f legacyScreenSaver 2>/dev/null || true
  rm -rf "$SAVER" "$SAVER_VIDEO"
  echo "Đã gỡ screensaver KuroTools Video và bản copy video của nó."
fi

echo "✓ Đã gỡ $DEST. Quạt trở lại Auto khi app thoát; helper root gỡ riêng bằng ./scripts/uninstall-helper.sh."
