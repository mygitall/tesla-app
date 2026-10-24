#!/bin/bash
# 用法：./add-car-image.sh 你的车图片.jpg
# 作用：自动转换格式、生成资源、重新打包 IPA 到桌面
set -euo pipefail

SRC="${1:-}"
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
  echo "用法: ./add-car-image.sh <图片路径>"
  echo "示例: ./add-car-image.sh ~/Desktop/我的车.jpg"
  exit 1
fi

cd "$(dirname "$0")"
ASSET="teslaapp/Assets.xcassets/car.imageset"
mkdir -p "$ASSET"

echo "① 转换图片为 PNG（最长边不超过 1400px）"
TMP="/tmp/car_src.$$"
EXT=$(echo "${SRC##*.}" | tr 'A-Z' 'a-z')
case "$EXT" in
  png) cp "$SRC" "$TMP.png" ;;
  *)   sips -s format png "$SRC" --out "$TMP.png" >/dev/null 2>&1 ;;
esac
# 只缩小、不放大（放大只会变模糊）
W=$(sips -g pixelWidth "$TMP.png" 2>/dev/null | awk '/pixelWidth/{print $2}')
if [ "${W:-0}" -gt 1400 ]; then
  sips --resampleHeightWidthMax 1400 "$TMP.png" --out "$TMP.small.png" >/dev/null 2>&1
else
  cp "$TMP.png" "$TMP.small.png"
fi
cp "$TMP.small.png" "$ASSET/car.png"
rm -f "$TMP" "$TMP.png" "$TMP.small.png"
echo "   ✓ $(du -h "$ASSET/car.png" | cut -f1)  $(sips -g pixelWidth -g pixelHeight "$ASSET/car.png" 2>/dev/null | awk '/pixel/{printf "%s ", $2}')"

echo "② 写入资源描述"
cat > "$ASSET/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "car.png", "idiom" : "universal", "scale" : "1x" },
    { "idiom" : "universal", "scale" : "2x" },
    { "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "③ 重新生成工程并编译"
xcodegen generate >/dev/null 2>&1
xcodebuild -project teslaapp.xcodeproj -scheme teslaapp -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/tesla-car \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build 2>&1 | grep -E "error:" | head -5 || true

APP="/tmp/tesla-car/Build/Products/Release-iphoneos/Tesla.app"
if [ ! -d "$APP" ]; then echo "   ✗ 编译失败"; exit 1; fi

echo "④ 打包 IPA"
rm -rf /tmp/pkgcar && mkdir -p /tmp/pkgcar/Payload && cp -R "$APP" /tmp/pkgcar/Payload/
cd /tmp/pkgcar && rm -f "$HOME/Desktop/TeslaBLE.ipa" && zip -qry "$HOME/Desktop/TeslaBLE.ipa" Payload
echo "   ✓ ~/Desktop/TeslaBLE.ipa  $(du -h "$HOME/Desktop/TeslaBLE.ipa" | cut -f1)"
echo
echo "完成！装这个 IPA，首页就会显示你的车图。"
