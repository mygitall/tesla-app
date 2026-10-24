#!/bin/bash
# 一键：编译 + 装到模拟器 + 启动
# 用法：./run-sim.sh
set -e
cd "$(dirname "$0")"
DEV="FA545AA7-030E-4AB2-8A0C-EA2247945C0C"

echo "① 编译中…"
xcodebuild -project teslaapp.xcodeproj -scheme teslaapp -sdk iphonesimulator \
  -configuration Debug -derivedDataPath /tmp/tesla-run \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD SUCCEEDED" | head -5

APP="/tmp/tesla-run/Build/Products/Debug-iphonesimulator/Tesla.app"
[ -d "$APP" ] || { echo "✗ 编译失败"; exit 1; }

echo "② 安装到模拟器…"
xcrun simctl boot "$DEV" 2>/dev/null || true
open -a Simulator
sleep 3
xcrun simctl install "$DEV" "$APP"
echo "③ 启动…"
xcrun simctl terminate "$DEV" com.zhangweiwei.teslaapp 2>/dev/null || true
xcrun simctl launch "$DEV" com.zhangweiwei.teslaapp
echo "✓ 完成，看模拟器窗口"
