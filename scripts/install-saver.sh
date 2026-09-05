#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/Library/Screen Savers/KuroToolsWallpaper.saver"

# Trong gói tải về, .saver đã build sẵn nằm cạnh script và máy đó không có
# toolchain để build lại; trong repo thì build từ nguồn như trước.
if [ -d "$HERE/KuroToolsWallpaper.saver" ]; then
  SRC="$HERE/KuroToolsWallpaper.saver"
else
  ROOT="$(cd "$HERE/.." && pwd)"
  "$ROOT/scripts/bundle-saver.sh"
  SRC="$ROOT/KuroToolsWallpaper.saver"
fi

# Engine giữ bundle CŨ trong bộ nhớ: cài đè mà không giết nó thì lần chạy sau
# vẫn là code cũ, và ta ngồi debug một bản build không tồn tại trên đĩa nữa.
pkill -f legacyScreenSaver 2>/dev/null || true
pkill -x ScreenSaverEngine 2>/dev/null || true

mkdir -p "$HOME/Library/Screen Savers"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "✓ Đã cài $DEST"
echo "  Chọn 'KuroTools Video' trong System Settings ▸ Screen Saver."
echo "  Chưa chọn video trong Settings ▸ Chung thì nó hiện nền đen kèm dòng chỉ đường."
open "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"
