# 对齐进度面板 — <分支名> ← <主干>

> 由 qiq-alignmain 维护。本文件是本次对齐的单一进度视图与回退锚点记录。

## 基本信息

| 项 | 值 |
|---|---|
| 工作分支 | `<分支名>` |
| 主干分支 | `origin/<主干>` |
| merge-base | `<merge-base commit>` |
| 启动时间 | `<YYYYMMDD-HHMMSS>` |

## 回退锚点（出错时据此恢复，仅用户要求放弃时执行）

| 锚点 | 值 | 恢复方式 |
|---|---|---|
| 合流前 HEAD | `<commit hash>` | merge 中途 `git merge --abort`；已生成 merge commit 且确认放弃 `git reset --hard <hash>` |
| 暂存方式 | `stash` / `WIP commit` / `无` | 见下 |
| stash 引用 / WIP commit | `stash@{N}` 或 `<wip hash>` | Phase 5 `git stash pop` / `git reset --soft HEAD~1` |

## 阶段进度

| Phase | 名称 | 状态 | 产物 |
|---|---|---|---|
| 0 | 确认分支与仓库状态 | ⬜ pending / 🔄 doing / ✅ done | 本文件 |
| 1 | 暂存未提交改动 | ⬜ | 本文件回退锚点 |
| 2 | 合流前逻辑冲突检查 ★ | ⬜ | `LOGICAL_CONFLICTS.md` |
| 3 | merge 主干 | ⬜ | — |
| 4 | 行冲突解决 | ⬜ | `CONFLICT_RESOLUTION.md` |
| 5 | 合流后整体审查 ★ | ⬜ | `POST_MERGE_REVIEW.md` |

★ = STOP & CONFIRM 关口，需用户确认。

## 当前待人工确认项

- （列出所有 NEEDS-HUMAN / 高风险未决项；为空则写"无"）
