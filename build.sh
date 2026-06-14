#!/usr/bin/env bash
# 构建 ccMonitor.app 到 ./build 目录
set -euo pipefail
cd "$(dirname "$0")"

SCHEME="ccMonitor"
PROJECT="ccMonitor.xcodeproj"
CONFIG="${1:-Release}"

# 若装了 xcodegen，先从 project.yml 重新生成工程（保证文件列表最新）
if command -v xcodegen >/dev/null 2>&1; then
  echo "==> xcodegen generate"
  xcodegen generate
fi

echo "==> 构建 $SCHEME ($CONFIG)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath ./build \
  build

APP="./build/Build/Products/$CONFIG/ccMonitor.app"
echo "==> 完成: $APP"
echo "运行: open \"$APP\""
