#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# PHẢI khớp `ProgramArguments` trong `Sources/KuroTools/LaunchAgent.plist`:
# plist đó nằm TRONG bundle và hardcode một đường dẫn tuyệt đối, nên cài ra chỗ
# khác nghĩa là login item đăng ký thành công mà launchd lại khởi động một
# đường dẫn không tồn tại — công tắc "Chạy khi đăng nhập" bật, và sáng hôm sau
# app không lên. `LoginItemTests` ràng hai giá trị này lại với nhau.
DEST="/Applications/KuroTools.app"
# LaunchAgent viết tay của thời KuroVitals. Nó có LABEL RIÊNG
# (`com.kuro.kurovitals.app`) nên launchd coi nó hoàn toàn khác login item mà
# app tự đăng ký (`com.kuro.kurotools.app`): còn cả hai thì hai bản KuroTools
# cùng tự chạy lúc đăng nhập, cùng giành SMC và cùng đăng ký một hotkey.
LEGACY_PLIST="$HOME/Library/LaunchAgents/com.kuro.kurovitals.app.plist"

# Script này KHÔNG còn dựng autostart nào của riêng nó. Từ M2, "chạy khi đăng
# nhập" là việc của chính app: `SMAppService.agent(plistName:)` + công tắc
# trong Settings ▸ Chung, dùng plist đã nằm sẵn trong bundle. Phần duy nhất
# SMAppService không làm được là đưa bundle đã ký vào đúng $DEST — đó là toàn
# bộ việc của script này.
"$ROOT/scripts/bundle-app.sh"

# Bản đang chạy phải THOÁT ĐÚNG CÁCH trước khi bị ghi đè: `applicationWillTerminate`
# là nơi quạt được trả về Auto. SIGTERM (`pkill`) bỏ qua bước đó và để quạt kẹt
# ở RPM ép cuối cùng cho tới khi helper hết TTL.
if pgrep -f "$DEST/Contents/MacOS/KuroTools" >/dev/null 2>&1; then
  echo "Đang thoát bản KuroTools đang chạy…"
  osascript -e 'quit app "KuroTools"' >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -f "$DEST/Contents/MacOS/KuroTools" >/dev/null 2>&1 || break
    sleep 0.5
  done
  # Không tự ép: `rm -rf` một bundle đang chạy để lại một bản cài vỡ, và
  # người dùng còn cửa sổ menu bar ngay trước mặt để tự thoát.
  if pgrep -f "$DEST/Contents/MacOS/KuroTools" >/dev/null 2>&1; then
    echo "⚠ KuroTools vẫn đang chạy. Thoát nó từ menu bar rồi chạy lại script này." >&2
    exit 1
  fi
fi

rm -rf "$DEST"
cp -R "$ROOT/KuroTools.app" "$DEST"

if [ -f "$LEGACY_PLIST" ]; then
  # Chỉ GỠ, không bao giờ tạo (xem chú thích ở $LEGACY_PLIST). `bootout` có thể
  # báo lỗi nếu agent chưa được nạp — xoá file mới là phần quyết định cho lần
  # đăng nhập sau.
  launchctl bootout "gui/$(id -u)/com.kuro.kurovitals.app" 2>/dev/null || true
  rm -f "$LEGACY_PLIST"
  echo "Đã gỡ LaunchAgent viết tay cũ (com.kuro.kurovitals.app) — nó sẽ làm hai bản cùng tự chạy."
fi

open "$DEST"
echo "✓ Đã cài $DEST và mở app."
echo "  Bật 'Chạy khi đăng nhập' trong Settings ▸ Chung nếu muốn nó tự lên lúc đăng nhập."
echo "  Gỡ: ./scripts/uninstall-app.sh"
