#!/bin/bash
# 用 py2app 打独立 App：Python 运行时、PyObjC、luma 全部塞进 Luma.app。
# 产物：dist/Luma.app（Dock 里显示 Luma，不显示 Python）
set -euo pipefail
cd "$(dirname "$0")"

BUILD_VENV=".build-venv"

if [ ! -x "$BUILD_VENV/bin/python" ]; then
  BASE=""
  for cand in /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3 \
              /usr/local/bin/python3; do
    if [ -x "$cand" ]; then BASE="$cand"; break; fi
  done
  if [ -z "$BASE" ]; then
    echo "没找到 python3，无法构建"; exit 1
  fi
  echo "创建构建环境（只用于打包，不会装进 App）…"
  "$BASE" -m venv "$BUILD_VENV"
  "$BUILD_VENV/bin/python" -m pip install --quiet --disable-pip-version-check \
    pyobjc-framework-Cocoa py2app setuptools
fi

rm -rf build dist
"$BUILD_VENV/bin/python" setup.py py2app >/tmp/luma-py2app.log 2>&1 || {
  echo "构建失败，日志见 /tmp/luma-py2app.log"
  tail -30 /tmp/luma-py2app.log
  exit 1
}

if [ ! -d dist/Luma.app ]; then
  echo "构建失败：没有生成 dist/Luma.app"
  exit 1
fi

codesign --force --deep --sign - dist/Luma.app >/dev/null 2>&1 || true
echo "已生成 dist/Luma.app（$(du -sh dist/Luma.app | cut -f1)）"
