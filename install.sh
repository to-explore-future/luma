#!/bin/bash
# 安装 Luma：装到 /Applications，可选开机自启和命令行入口
set -euo pipefail
cd "$(dirname "$0")"

WITH_LOGIN=0
WITH_CLI=0
for arg in "$@"; do
  case "$arg" in
    --login) WITH_LOGIN=1 ;;
    --cli)   WITH_CLI=1 ;;
    *) echo "未知参数：$arg"; exit 2 ;;
  esac
done

if [ -w /Applications ]; then
  DEST="/Applications/Luma.app"
else
  DEST="$HOME/Applications/Luma.app"
fi

./build.sh

# 停掉旧实例，避免新旧两份同时抢亮度
pkill -f -- "-m luma" 2>/dev/null || true
pkill -f "Luma.app/Contents/MacOS/Luma" 2>/dev/null || true

rm -rf "$DEST" "$HOME/Applications/Luma.app"
cp -R dist/Luma.app "$DEST"
echo "已安装到 $DEST"

if [ "$WITH_CLI" = "1" ]; then
  BIN="$HOME/.local/bin"
  mkdir -p "$BIN"
  ln -sf "$DEST/Contents/MacOS/Luma" "$BIN/luma"
  echo "已创建命令：$BIN/luma"
fi

if [ "$WITH_LOGIN" = "1" ]; then
  "$DEST/Contents/MacOS/Luma" login on
fi

echo
echo "接下来："
echo "  1) 退出 MonitorControl（两个程序都会调亮度，会互相抢）"
echo "  2) 启动：open \"$DEST\""
echo "  3) Dock 里会出现 Luma，窗口里有每块屏的滑块"
