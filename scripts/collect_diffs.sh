#!/usr/bin/env bash
# collect_diffs.sh — 为 qiq-alignmain Phase 2 逻辑冲突检查收集双方改动概览。
#
# 用法:
#   bash scripts/collect_diffs.sh <trunk_ref> [merge_base]
#
# 参数:
#   trunk_ref    主干引用，通常是 origin/main（必填）
#   merge_base   共同祖先 commit；省略则自动用 `git merge-base HEAD <trunk_ref>` 计算
#
# 输出（只读，不修改仓库）:
#   1. 主干侧改动概览     merge_base -> trunk
#   2. 分支侧改动概览     merge_base -> HEAD
#   3. 双方共同触碰的文件（行冲突 + 语义冲突高发交集）
#   4. 主干侧的 rename/delete 文件（模块搬迁/删除类语义冲突线索）
#
# 设计为安全只读：仅调用 git diff / git merge-base 等查询命令。

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "用法: bash scripts/collect_diffs.sh <trunk_ref> [merge_base]" >&2
  echo "示例: bash scripts/collect_diffs.sh origin/main" >&2
  exit 1
fi

TRUNK="$1"

# 确认在 git 仓库内
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "错误: 当前目录不是 git 仓库。" >&2
  exit 1
fi

# 确认 trunk 引用存在
if ! git rev-parse --verify --quiet "${TRUNK}^{commit}" >/dev/null; then
  echo "错误: 主干引用 '${TRUNK}' 不存在或无效（是否需要先 git fetch?）。" >&2
  exit 1
fi

if [ "$#" -ge 2 ]; then
  MB="$2"
else
  MB="$(git merge-base HEAD "$TRUNK")"
fi

if ! git rev-parse --verify --quiet "${MB}^{commit}" >/dev/null; then
  echo "错误: merge-base '${MB}' 无效。" >&2
  exit 1
fi

CUR_BRANCH="$(git branch --show-current 2>/dev/null || echo '(detached)')"

echo "================================================================"
echo " qiq-alignmain 双方改动概览"
echo "   工作分支 : ${CUR_BRANCH} (HEAD=$(git rev-parse --short HEAD))"
echo "   主干     : ${TRUNK} ($(git rev-parse --short "$TRUNK"))"
echo "   merge-base: $(git rev-parse --short "$MB")"
echo "================================================================"

echo ""
echo "----- [1] 主干侧改动（merge-base -> ${TRUNK}）：线上/主干这段时间改了什么 -----"
git --no-pager diff --stat "$MB" "$TRUNK" || true

echo ""
echo "----- [2] 分支侧改动（merge-base -> HEAD）：本分支这段时间改了什么 -----"
git --no-pager diff --stat "$MB" "HEAD" || true

echo ""
echo "----- [3] 双方共同触碰的文件（优先精读 diff）-----"
COMMON="$(comm -12 \
  <(git diff --name-only "$MB" "$TRUNK" | sort -u) \
  <(git diff --name-only "$MB" "HEAD" | sort -u) || true)"
if [ -n "$COMMON" ]; then
  echo "$COMMON"
else
  echo "(无共同触碰文件 —— 注意：仍可能存在跨文件的接口/契约语义冲突，需按 7 类清单排查)"
fi

echo ""
echo "----- [4] 主干侧 rename/delete 文件（模块搬迁/删除类冲突线索）-----"
git --no-pager diff --name-status --diff-filter=RD "$MB" "$TRUNK" || true

echo ""
echo "================================================================"
echo " 下一步：对 [3] 逐文件精读 git diff；对主干侧变更的函数/字段/契约，"
echo "         在分支侧 grep 其调用/引用点，按 7 类语义冲突清单逐类登记。"
echo "================================================================"
