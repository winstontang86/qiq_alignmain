---
name: qiq-alignmain
description: 把主干（main/master/develop）的最新修改安全对齐（合流）到当前工作分支。覆盖确认分支、暂存未提交改动、合流前逻辑冲突检查、merge 主干、行冲突解决、合流后整体审查。重点检测 git 不报行冲突但逻辑互相破坏的语义冲突，并在“不回滚已有逻辑”“完整实现分支目标”两条硬约束下解决冲突，不可兼得时停下交人工确认。触发：把 main 对齐到分支 / 合流主干 / merge main 到当前分支 / align main / 同步主干 / 解决主干合流冲突。
version: 0.1.0
---

# qiq-alignmain — 把主干修改安全对齐到工作分支

## When to use

满足任一条件即启用：

- 用户要把 `main` / `master` / `develop` 等主干最新改动合流到当前开发分支。
- 用户提到：**把 main 对齐到分支 / 合流主干 / merge main / align main / 同步主干 / 拉取主干最新代码 / 解决主干合流冲突**。
- 用户希望合流过程可回退、可审计，并能检查 git 不会报告的逻辑冲突。

不适用：新建/切换分支、把分支合回主干、提交 MR、发布上线、非 git 仓库环境。

## 核心原则

1. **方向单一**：只做 **主干 → 当前工作分支**，绝不反向污染主干。
2. **可回退优先**：merge / stash pop / reset 前必须记录合流前 `HEAD`、stash/WIP 等锚点。
3. **先查逻辑冲突**：git 无行冲突 ≠ 无语义冲突；必须在 merge 前主动检查并落盘。
4. **冲突解决两条硬约束**：结果必须同时保留主干与分支已有有效逻辑，并完整实现分支本次目标；不可兼得则标记 `NEEDS-HUMAN` 并停下。
5. **不擅自发挥**：合流不是重构，禁止借机改名、删功能、做未要求优化。
6. **全程可审计**：逻辑冲突、行冲突、stash pop 二次冲突都要逐条记录；记录条数必须能和 git 冲突块数对账。

## 按需加载索引

主入口保留流程骨架；执行到对应阶段时再读取 reference/template 的完整细节。

| 阶段 | 目标 | 必读 reference | 必读 template |
|---|---|---|---|
| Phase 0/1 | 确认分支、fetch 主干、安全暂存 | `references/01-preflight.md` | `templates/ALIGN_PROGRESS.md` |
| Phase 2 ★ | 合流前逻辑冲突检查，产出清单并确认 | `references/02-logical-conflict-check.md` | `templates/LOGICAL_CONFLICTS.md` |
| Phase 3/4 | merge 主干；逐块解决并记录行冲突 | `references/03-merge-and-resolve.md` | `templates/CONFLICT_RESOLUTION.md` |
| Phase 5 ★ | 合流后审查：覆盖线上功能、引入 bug、stash/WIP 恢复 | `references/04-post-merge-review.md` | `templates/POST_MERGE_REVIEW.md` |

辅助脚本：`scripts/collect_diffs.sh origin/<主干>`，用于 Phase 2 收集主干侧 diff、分支侧 diff、共同改动文件、主干侧 rename/delete 概览。

## Workflow

```text
Phase 0 确认工作分支、主干分支、仓库状态，建立产物目录
  ↓
Phase 1 暂存未提交改动，记录回退锚点
  ↓
Phase 2 ★ 合流前逻辑冲突检查，写 LOGICAL_CONFLICTS.md，STOP & CONFIRM
  ↓
Phase 3 merge origin/<主干>
  ↓
Phase 4 如有行冲突，逐块解决并写 CONFLICT_RESOLUTION.md
  ↓
Phase 5 ★ 合流后整体审查，写 POST_MERGE_REVIEW.md，STOP & CONFIRM
```

### Phase 0 — 确认工作分支与主干

按 `references/01-preflight.md` §0 执行：

- 确认在 git 仓库内，且不处于 detached HEAD、rebase/merge 中途等异常状态。
- 工作分支默认取当前分支；用户显式指定时再切换并复核。
- 主干优先取远端默认分支；候选不唯一时询问用户。合流目标默认使用 `origin/<主干>`。
- 执行 `git fetch origin <主干> --prune`，不对工作分支执行 `git pull`。
- 计算 `merge-base`，记录合流前 `HEAD`、主干 commit 等锚点。
- 在工作仓库根目录建立 `.qiqskills/<仓库名>-<分支名>/`，初始化 `ALIGN_PROGRESS.md`。

### Phase 1 — 暂存未提交改动

按 `references/01-preflight.md` §1 执行：

- 工作区干净：记录“无需暂存”。
- 工作区不干净：默认 `git stash push -u -m "qiq-alignmain:<仓库名>-<分支名>:<时间戳>"`，并记录 stash 引用。
- 用户偏好提交时可使用 WIP commit，但必须记录 commit hash 与后续恢复方式。
- 禁止用 `reset --hard`、`checkout -- .`、`clean -fd` 等方式丢弃改动。

### Phase 2 — 合流前逻辑冲突检查（★STOP & CONFIRM）

按 `references/02-logical-conflict-check.md` 执行，这是本 skill 的核心价值：

1. 用 `scripts/collect_diffs.sh origin/<主干>` 或等价 git diff 收集双方从 `merge-base` 以来的改动。
2. 重点检查双方共同改动文件，以及“主干改接口/契约，分支仍按旧形态消费”的跨文件关系。
3. 按 7 类语义冲突逐类给结论：函数/方法签名、数据结构/字段、接口/契约、行为/默认值/常量、模块重构/搬迁/删除、共享资源/全局状态、依赖/构建/迁移。
4. 写 `.qiqskills/<仓库名>-<分支名>/LOGICAL_CONFLICTS.md`：包含冲突点、双方改动、风险等级、合流后修正预案；未发现也要写明已检查范围。
5. **STOP**：把清单交用户确认；高风险项必须达成处理共识后才进入 Phase 3。

### Phase 3 — merge 主干

按 `references/03-merge-and-resolve.md` §3 执行：

- 默认执行普通 merge：`git merge origin/<主干>`；不擅自改用 rebase。
- up-to-date：说明无需合流，并仍确认前置检查结果。
- 干净合入：进入 Phase 5，不能因 git 无冲突就跳过审查。
- 有行冲突：先收集冲突文件和冲突块总数，作为 Phase 4 对账基线。

### Phase 4 — 行冲突逐块解决与记录

按 `references/03-merge-and-resolve.md` §4 执行：

- 对每个冲突块读懂分支侧（`HEAD`）与主干侧（`origin/<主干>`）意图。
- 首选融合双方；如主干重构了结构，应把分支意图适配到主干新结构，而不是回滚主干。
- 若无法同时满足“不回滚已有逻辑”和“完整实现分支目标”，标记 `NEEDS-HUMAN`，停止并请用户裁决。
- 逐块写入 `CONFLICT_RESOLUTION.md`：文件/块定位、双方意图、解决方案、是否满足两条硬约束、是否需人工。
- 记录条数必须等于 Phase 3 统计的冲突块总数；所有 `NEEDS-HUMAN` 必须回填人工最终裁决后才能提交 merge。

### Phase 5 — 合流后整体审查（★STOP & CONFIRM）

按 `references/04-post-merge-review.md` 执行：

- 逐条核对 `LOGICAL_CONFLICTS.md`：确认高/中风险语义冲突已在合流结果中消化。
- 检查是否覆盖或回退了主干已有功能/修复，尤其是干净合入和偏向分支侧解决的位置。
- 检查是否引入 bug：签名、字段、契约、配置、依赖、迁移等是否一致；尽量运行构建/测试/lint。
- 处理 Phase 1 暂存：提示或执行 stash pop / WIP 恢复；若产生二次冲突，按 Phase 4 同样记录和对账。
- 写 `POST_MERGE_REVIEW.md`：逻辑冲突消化结果、覆盖线上功能结论、构建/测试结果、stash/WIP 处理、遗留风险。
- **STOP**：把审查结论交用户确认；存在未消化高风险项、未决人工项、构建/测试失败时，不宣告完成。

## 状态与产物目录约定

所有读写以用户工作仓库根目录为基准，产物固定写入：

```text
.qiqskills/<仓库名>-<分支名>/
├── ALIGN_PROGRESS.md
├── LOGICAL_CONFLICTS.md
├── CONFLICT_RESOLUTION.md
└── POST_MERGE_REVIEW.md
```

命名规则：`<仓库名>` 优先取 git remote 仓库名，无 remote 时取仓库根目录名；`<仓库名>` 与 `<分支名>` 中的 `/` 替换为 `-`。`.qiqskills/` 建议加入 `.gitignore`，除非用户希望提交审计记录。

## 红线（违反即停止）

- ❌ 向主干 push、把工作分支 merge/rebase 进主干、改写主干历史。
- ❌ 未记录回退锚点就执行 merge / stash pop / reset。
- ❌ 用 `reset --hard`、`checkout -- .`、`clean -fd` 等丢弃用户改动。
- ❌ 跳过 Phase 2 逻辑冲突检查直接 merge。
- ❌ 行冲突无法满足两条硬约束时擅自二选一。
- ❌ 用整文件 `--ours` / `--theirs` 图省事；确需使用必须逐块说明并记录。
- ❌ 借合流做无关重构、改名、删功能或顺手优化。
- ❌ 存在 `NEEDS-HUMAN`、未消化高风险项、构建/测试失败时提交或宣告完成。
- ❌ 只在对话中解决冲突而不落盘，或冲突记录无法与 git 冲突块数对账。

## Verification（交付前核对）

- [ ] 工作分支、主干分支、`merge-base`、合流前 `HEAD`、主干 commit、merge commit（如有）已记录。
- [ ] 未提交改动已安全暂存，或确认工作区干净。
- [ ] `LOGICAL_CONFLICTS.md` 已产出；7 类语义冲突已逐类排查并交用户确认。
- [ ] merge 结果已判定；如有行冲突，冲突文件与冲突块总数已在解决前存档。
- [ ] `CONFLICT_RESOLUTION.md` 逐块记录；记录条数与冲突块数一致；所有 `NEEDS-HUMAN` 已回填裁决。
- [ ] `POST_MERGE_REVIEW.md` 已产出；逻辑冲突预案、覆盖线上功能、引入 bug、构建/测试、stash/WIP 恢复均有结论。
