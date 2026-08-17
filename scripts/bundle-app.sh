#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/KuroTools.app"
IDENTITY="${KUROTOOLS_SIGNING_IDENTITY:-M97RK4Q68S}"
export MACOSX_DEPLOYMENT_TARGET=13.0

# App đang chạy sẽ giữ file và làm bước ký thất bại.
pkill -x KuroTools || true

# ⚠️ ĐI QUA `make rust`, đừng gọi cargo + swift build tay. Makefile giữ lá chắn
# stamp-hash: nếu .a đổi thì nó xoá .build để ép relink. Cách cũ (`touch` một
# file Swift) ĐÃ ĐƯỢC ĐO LÀ KHÔNG HOẠT ĐỘNG — swift-driver quyết định theo
# interface hash của module, không theo mtime hay nội dung file.
make -C "$ROOT" rust
swift build -c release --package-path "$ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/KuroTools" "$APP/Contents/MacOS/"
cp "$ROOT/Sources/KuroTools/Info.plist" "$APP/Contents/"

mkdir -p "$APP/Contents/Library/LaunchAgents"
cp Sources/KuroTools/LaunchAgent.plist "$APP/Contents/Library/LaunchAgents/com.kuro.kurotools.app.plist"

# Chữ ký ỔN ĐỊNH ngăn mỗi lần rebuild thu hồi quyền Accessibility.
codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --verbose "$APP"
echo "built: $APP"
