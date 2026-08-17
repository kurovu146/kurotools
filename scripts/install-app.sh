#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# PHẢI khớp `ProgramArguments` trong `Sources/KuroTools/LaunchAgent.plist`:
# plist đó nằm TRONG bundle và hardcode một đường dẫn tuyệt đối, nên cài ra chỗ
# khác nghĩa là login item đăng ký thành công mà launchd lại khởi động một
# đường dẫn không tồn tại — công tắc "Chạy khi đăng nhập" bật, và sáng hôm sau
# app không lên. `LoginItemTests` ràng hai giá trị này lại với nhau.
DEST="/Applications/KuroTools.app"
# LaunchAgent viết tay còn sót trong ~/Library/LaunchAgents. Sau M2 KHÔNG có
# cái nào trong hai cái này được phép tồn tại: agent hợp lệ duy nhất nằm TRONG
# bundle và do `SMAppService` quản.
#
#  - `com.kuro.kurovitals.app`: bản `install-app.sh` cũ dựng ra. Label RIÊNG
#    nên launchd coi nó hoàn toàn khác login item của app → hai bản KuroTools
#    cùng tự chạy lúc đăng nhập, cùng giành SMC, cùng đăng ký một hotkey.
#  - `com.kuro.kurotools.app`: nguy hiểm hơn vì nó TRÙNG label với agent trong
#    bundle — hai định nghĩa cho cùng một label trong cùng một domain launchd,
#    và công tắc "Chạy khi đăng nhập" không có cách nào gỡ được cái nằm ngoài
#    bundle.
LEGACY_LABELS="com.kuro.kurovitals.app com.kuro.kurotools.app"

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

for label in $LEGACY_LABELS; do
  plist="$HOME/Library/LaunchAgents/$label.plist"
  [ -f "$plist" ] || continue
  # Chỉ GỠ, không bao giờ tạo (xem chú thích ở $LEGACY_LABELS). `bootout` có
  # thể báo lỗi nếu agent chưa được nạp — xoá file mới là phần quyết định cho
  # lần đăng nhập sau.
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  rm -f "$plist"
  echo "Đã gỡ LaunchAgent viết tay cũ ($label) — nó tranh chỗ với công tắc trong Settings."
  echo "  → Bật lại 'Chạy khi đăng nhập' trong Settings ▸ Chung để app tự lên lúc đăng nhập."
done

open "$DEST"
echo "✓ Đã cài $DEST và mở app."
echo "  Bật 'Chạy khi đăng nhập' trong Settings ▸ Chung nếu muốn nó tự lên lúc đăng nhập."
echo "  Gỡ: ./scripts/uninstall-app.sh"
