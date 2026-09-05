#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/KuroTools.app"
# Chữ ký ỔN ĐỊNH giữ quyền Accessibility qua các lần rebuild: TCC neo quyền vào
# signing identity, đổi identity là mất quyền và phải cấp lại tay. Thứ tự tìm:
# biến môi trường → .signing-identity (không tracked, máy nào của người nấy) →
# ad-hoc. Ad-hoc để người không có tài khoản Apple Developer vẫn build được;
# đổi lại cdhash đổi theo từng bản build nên quyền Accessibility rụng mỗi lần.
IDENTITY="${KUROTOOLS_SIGNING_IDENTITY:-}"
if [ -z "$IDENTITY" ] && [ -r "$ROOT/.signing-identity" ]; then
  IDENTITY="$(tr -d "[:space:]" < "$ROOT/.signing-identity")"
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
  echo "⚠️  Ký ad-hoc — macOS sẽ hỏi lại quyền Accessibility sau MỖI lần build."
  echo "   Có tài khoản Apple Developer? Ghi Team ID vào .signing-identity để tránh."
fi
export MACOSX_DEPLOYMENT_TARGET=13.0

# App đang chạy sẽ giữ file và làm bước ký thất bại — nhưng CHỈ kill đúng bản
# build từ $APP. `pkill -x KuroTools` từng match theo TÊN process (không theo
# đường dẫn), nên nó giết luôn bản đã CÀI ở /Applications (LaunchAgent quản
# lý) y hệt bản repo-local này — bản cài đó phải sống sót qua một lần build ở
# đây, "khỏi bị giết" không phải nhờ KeepAlive hồi sinh nó may mắn.
pkill -f "$APP/Contents/MacOS/KuroTools" || true

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

# Nguồn phải neo vào "$ROOT" như mọi đường dẫn khác trong script: chạy từ một
# cwd khác thì `cp` tương đối hỏng dưới `set -e` — SAU khi `rm -rf "$APP"` ở
# trên đã xoá bundle cũ, để lại một bản cài biến mất và không có gì thay thế.
mkdir -p "$APP/Contents/Library/LaunchAgents"
cp "$ROOT/Sources/KuroTools/LaunchAgent.plist" "$APP/Contents/Library/LaunchAgents/com.kuro.kurotools.app.plist"

# ⚠️ PHẢI là bước ghi cuối cùng vào $APP — bước nào copy/ghi thêm SAU đây sẽ nằm ngoài resource seal, và "valid on disk" vẫn báo im lặng dù nội dung đã đổi sau khi ký.
# Chữ ký ỔN ĐỊNH ngăn mỗi lần rebuild thu hồi quyền Accessibility.
codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --verbose "$APP"
echo "built: $APP"
