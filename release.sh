#!/bin/bash
# 一条命令发版：升版本 → 打包 → 提交 → 打 tag → 建 GitHub Release → 上传 DMG
# 用法：
#   ./release.sh              正常发版
#   ./release.sh --dry-run    只做到打包/tag，不推送、不发 release
set -euo pipefail
cd "$(dirname "$0")"

DRY=0
NOTES_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --notes)   NOTES_ARG="${2:-}"; shift ;;
    *) echo "未知参数：$1"; exit 2 ;;
  esac
  shift
done

VERSION=$(sed -n 's/^VERSION = "\(.*\)"$/\1/p' luma/__init__.py | head -1)
TAG="v$VERSION"
DMG="dist/Luma-$VERSION.dmg"

echo "==> 版本：${VERSION}，tag：${TAG}"
./make-dmg.sh

# 有改动就提交（版本号通常在发版前已经改好）
if [ "$DRY" != "1" ] && { ! git diff --quiet || ! git diff --cached --quiet; }; then
  git add -A
  git commit -m "release: $TAG"
fi

if [ -n "$NOTES_ARG" ]; then
  NOTES="$NOTES_ARG"
fi

PREV=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [ -z "$NOTES_ARG" ]; then
  if [ -n "$PREV" ]; then
    NOTES=$(git log --pretty=format:"- %s" "$PREV..HEAD" 2>/dev/null || true)
  else
    NOTES=$(git log --pretty=format:"- %s" | head -20)
  fi
fi
[ -z "$NOTES" ] && NOTES="- $TAG"

if [ "$DRY" = "1" ]; then
  echo "==> dry-run：跳过推送与 Release"
  echo "--- release notes ---"
  echo "$NOTES"
  exit 0
fi

git push origin HEAD
git tag -f "$TAG"
git push -f origin "$TAG"

# gh 需要走本地代理（这台机器直连 github.com 不通）
if [ -z "${HTTPS_PROXY:-}" ]; then
  for port in 7897 7890 1087 1080 6152; do
    if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      export HTTPS_PROXY="http://127.0.0.1:$port"
      export HTTP_PROXY="$HTTPS_PROXY"
      echo "==> 使用本地代理 $HTTPS_PROXY"
      break
    fi
  done
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "没装 gh：请先 brew install gh && gh auth login"; exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "还没登录 GitHub：请先跑一次  gh auth login"; exit 1
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "==> 该 tag 的 Release 已存在，覆盖上传 DMG"
  gh release upload "$TAG" "$DMG" --clobber
else
  echo "==> 创建 Release $TAG"
  gh release create "$TAG" "$DMG" \
    --title "Luma $VERSION" \
    --notes "$NOTES"
fi

echo "==> 完成：https://github.com/to-explore-future/luma/releases/tag/$TAG"
