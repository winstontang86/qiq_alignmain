#!/usr/bin/env bash
# build.sh — 把 qiq-alignmain skill 打包为可分发 zip。
#
# 用法:
#   bash scripts/build.sh              # 打包，版本号自动推断
#   VERSION=v0.1.0 bash scripts/build.sh   # 显式指定版本号
#   bash scripts/build.sh --no-zip     # 仅校验，不打包
#
# 产物:
#   dist/qiq-alignmain-<version>.zip
#     └── qiq-alignmain/   (SKILL.md / README.md / LICENSE / references/ / templates/ / scripts/)
#
# 版本号优先级: 环境变量 VERSION > SKILL.md frontmatter `version:` > git describe > 日期戳。

set -euo pipefail

SKILL_NAME="qiq-alignmain"

# 仓库根 = scripts/ 的上一级
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

NO_ZIP=0
[ "${1:-}" = "--no-zip" ] && NO_ZIP=1

# ---- 解析版本号 ----
resolve_version() {
  if [ -n "${VERSION:-}" ]; then
    echo "$VERSION"; return
  fi
  local v
  v="$(grep -m1 -E '^version:' SKILL.md 2>/dev/null | sed -E 's/^version:[[:space:]]*//; s/[[:space:]]*$//')"
  if [ -n "$v" ]; then echo "v$v"; return; fi
  if v="$(git describe --tags --always 2>/dev/null)"; then echo "$v"; return; fi
  date +%Y%m%d
}
VER="$(resolve_version)"

echo "==> 打包 ${SKILL_NAME} (version=${VER})"

# ---- 校验 ----
fail=0

if [ ! -f SKILL.md ]; then
  echo "ERROR: 缺少 SKILL.md" >&2; fail=1
else
  grep -qE '^name:[[:space:]]*\S' SKILL.md       || { echo "ERROR: SKILL.md frontmatter 缺少 name:" >&2; fail=1; }
  grep -qE '^description:[[:space:]]*\S' SKILL.md || { echo "ERROR: SKILL.md frontmatter 缺少 description:" >&2; fail=1; }
fi

# 内部链接校验（指向 .md / .json / .sh 的相对链接，目标须存在；仅 WARN）
# 整段在关闭 errexit/pipefail 下运行，避免 grep 无匹配导致脚本退出。
check_links() {
  set +e +o pipefail
  local f link target dir
  while IFS= read -r f; do
    grep -oE '\(([^)]+\.(md|json|sh))\)' "$f" 2>/dev/null | sed -E 's/^\(|\)$//g' | while IFS= read -r link; do
      case "$link" in
        http*|/*|'') continue ;;
      esac
      dir="$(cd "$(dirname "$f")" 2>/dev/null && cd "$(dirname "$link")" 2>/dev/null && pwd)"
      [ -n "$dir" ] && [ -f "$dir/$(basename "$link")" ] || echo "WARN: $f 引用的 $link 不存在" >&2
    done
  done < <(find . -name '*.md' -not -path './dist/*' -not -path './.git/*')
  set -e -o pipefail
}
check_links

if [ "$fail" -ne 0 ]; then
  echo "==> 校验失败，终止。" >&2
  exit 1
fi
echo "==> 校验通过。"

if [ "$NO_ZIP" -eq 1 ]; then
  echo "==> --no-zip：仅校验，不打包。"
  exit 0
fi

# ---- 打包 ----
command -v zip >/dev/null 2>&1 || { echo "ERROR: 未找到 zip 命令。" >&2; exit 1; }

DIST="$ROOT/dist"
rm -rf "$DIST"
STAGE="$DIST/$SKILL_NAME"
mkdir -p "$STAGE"

# 待打包清单（仅纳入 skill 真正需要的文件，排除 dist/.git 等）
for item in SKILL.md README.md LICENSE references templates scripts; do
  [ -e "$item" ] && cp -r "$item" "$STAGE/"
done

# 不把 build.sh 自身打进发布包（它是开发期工具）
rm -f "$STAGE/scripts/build.sh"

ZIP="$DIST/${SKILL_NAME}-${VER}.zip"
( cd "$DIST" && zip -r -q "$(basename "$ZIP")" "$SKILL_NAME" )
rm -rf "$STAGE"

echo "==> 完成: ${ZIP}"
echo "    内容:"
unzip -l "$ZIP" | sed 's/^/    /'
