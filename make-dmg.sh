#!/bin/bash
# 打包 DMG：Luma.app + Applications 快捷方式 + 使用说明
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0.4"
STAGE="dmg-stage"
DMG="dist/Luma-$VERSION.dmg"

./build.sh

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R dist/Luma.app "$STAGE/Luma.app"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/使用说明.txt" <<'TXT'
Luma — macOS 亮度控制（睡眠唤醒后不会变回最亮）

安装
  1. 把左边的 Luma.app 拖进右边的 Applications（应用程序）文件夹
  2. 打开 Luma，菜单栏会出现一个小太阳，同时弹出亮度窗口
  3. 不需要联网、不需要装 Python，App 自带运行环境

使用
  窗口里每块屏一行滑块，拖到你要的亮度，自动记住。
  睡眠唤醒后自动恢复。关掉窗口不退出，点菜单栏小太阳可再打开。
  这个 App 不占 Dock、不进 Cmd-Tab；万一菜单栏图标被系统藏了，
  去「应用程序」里双击 Luma 也能把窗口叫出来。

开机自启
  窗口左下角「自启:关」点一下变成「自启:开」。

命令行（可选）
  /Applications/Luma.app/Contents/MacOS/Luma list
  /Applications/Luma.app/Contents/MacOS/Luma set 60 aoc

注意
  · 不要和 MonitorControl 同时运行，两个程序都会抢亮度。
  · AOC 这类不支持原生亮度的外接屏走「软件调光」，需要 Luma 常驻才有粘性。
TXT

hdiutil create -volname "Luma" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "已生成 $DMG"
ls -lh "$DMG"
