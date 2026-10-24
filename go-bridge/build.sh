#!/bin/bash
# 重新生成 iOS 用的 Go 框架（协议层复用特斯拉官方实现）
#
# 前置：go、gomobile 已安装
#   go install golang.org/x/mobile/cmd/gomobile@latest
#   gomobile init
#
# 用法：./go-bridge/build.sh
set -euo pipefail
export GOPROXY=https://goproxy.cn,direct
export PATH="$PATH:$HOME/go/bin"

VC="${VC:-/tmp/vc}"          # vehicle-command 源码目录
OUT="$(cd "$(dirname "$0")/.." && pwd)/Frameworks"

if [ ! -d "$VC" ]; then
  echo "缺少 vehicle-command 源码，先执行："
  echo "  GOFLAGS=-mod=mod go mod download github.com/teslamotors/vehicle-command"
  echo "  或 git clone https://github.com/teslamotors/vehicle-command $VC"
  exit 1
fi

mkdir -p "$VC/mobilebridge"
cp "$(dirname "$0")/bridge.go" "$VC/mobilebridge/bridge.go"

cd "$VC"
go get -tool golang.org/x/mobile/cmd/gobind >/dev/null 2>&1 || true
mkdir -p "$OUT"
rm -rf "$OUT/TeslaBLE.xcframework"
gomobile bind -target=ios -o "$OUT/TeslaBLE.xcframework" ./mobilebridge
echo "✓ 已生成 $OUT/TeslaBLE.xcframework"
