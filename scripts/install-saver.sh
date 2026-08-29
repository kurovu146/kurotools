#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/Library/Screen Savers/KuroToolsWallpaper.saver"

"$ROOT/scripts/bundle-saver.sh"

# Engine giữ bundle CŨ trong bộ nhớ: cài đè mà không giết nó thì lần chạy sau
# vẫn là code cũ, và ta ngồi debug một bản build không tồn tại trên đĩa nữa.
pkill -f legacyScreenSaver 2>/dev/null || true
pkill -x ScreenSaverEngine 2>/dev/null || true

mkdir -p "$HOME/Library/Screen Savers"
rm -rf "$DEST"
cp -R "$ROOT/KuroToolsWallpaper.saver" "$DEST"

echo "✓ Đã cài $DEST"
echo "  Chọn 'KuroTools Video' trong System Settings ▸ Screen Saver."
echo "  Chưa chọn video trong Settings ▸ Chung thì nó hiện nền đen kèm dòng chỉ đường."
open "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"
