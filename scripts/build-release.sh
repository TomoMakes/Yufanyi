#!/bin/bash
# 构建发布用的 App 与 DMG（未签名，使用临时签名）。
# 用法：scripts/build-release.sh 版本号     例如：scripts/build-release.sh 0.1.0-beta
set -euo pipefail
VERSION="${1:?请提供版本号，例如 0.1.0-beta}"
SRC="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$SRC/build"
DERIVED="$OUT/derived"
mkdir -p "$OUT"

# 关闭代码覆盖率插桩，并把源码路径映射为 /src，避免构建机的本地路径写入二进制。
xcodebuild -project "$SRC/ScreenTranslate.xcodeproj" -scheme ScreenTranslate -configuration Release \
  -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' \
  CLANG_COVERAGE_MAPPING=NO CLANG_ENABLE_CODE_COVERAGE=NO CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO \
  DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
  "OTHER_SWIFT_FLAGS=\$(inherited) -file-prefix-map $SRC=/src -debug-prefix-map $SRC=/src" \
  "OTHER_CFLAGS=\$(inherited) -ffile-prefix-map=$SRC=/src" build

APP="$DERIVED/Build/Products/Release/ScreenTranslate.app"
strip -x -S "$APP/Contents/MacOS/ScreenTranslate"
codesign --force --deep -s - "$APP"

STAGE="$OUT/dmg"
rm -rf "${STAGE:?}"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/预翻译 for Mac.app"
ln -s /Applications "$STAGE/应用程序"
cp "$SRC/guide/使用说明.txt" "$STAGE/使用说明.txt"
hdiutil create -volname "预翻译 for Mac" -srcfolder "$STAGE" -ov -format UDZO "$OUT/Yufanyi-$VERSION.dmg"
shasum -a 256 "$OUT/Yufanyi-$VERSION.dmg"
