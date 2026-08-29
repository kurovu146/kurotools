#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SAVER="$ROOT/KuroToolsWallpaper.saver"
IDENTITY="${KUROTOOLS_SIGNING_IDENTITY:-M97RK4Q68S}"
export MACOSX_DEPLOYMENT_TARGET=13.0

# Đi qua `make rust` như bundle-app.sh: Makefile giữ lá chắn stamp-hash, bỏ qua
# nó thì swift build có thể link vào một .a cũ.
make -C "$ROOT" rust
swift build -c release --package-path "$ROOT" --product KuroToolsWallpaper

rm -rf "$SAVER"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"
cp "$ROOT/.build/release/libKuroToolsWallpaper.dylib" "$SAVER/Contents/MacOS/KuroToolsWallpaper"
# Install name mặc định trỏ về .build của repo. Bundle được `dlopen` theo đường
# dẫn tuyệt đối nên nó không quyết định gì, nhưng để nguyên là để lại một đường
# dẫn máy-cụ-thể trong binary đã ký.
install_name_tool -id KuroToolsWallpaper "$SAVER/Contents/MacOS/KuroToolsWallpaper"

cat > "$SAVER/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>KuroToolsWallpaper</string>
  <key>CFBundleIdentifier</key><string>com.kurovu146.kurotools.wallpaper.saver</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>KuroTools Video</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>KTWallpaperSaverView</string>
</dict>
</plist>
PLIST

# PHẢI là bước ghi cuối cùng — y hệt bundle-app.sh: thứ gì ghi vào bundle sau
# khi ký sẽ nằm ngoài resource seal.
codesign --force --options runtime --sign "$IDENTITY" "$SAVER"
codesign --verify --verbose "$SAVER"
echo "built: $SAVER"
