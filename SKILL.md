---
name: qiq-alignmain
description: 把主干（main/master）的最新修改安全对齐（合流）到当前工作分支的工程化工作流。覆盖确认分支、暂存未提交改动、合流前逻辑冲突检查、merge main、行冲突解决、合流后整体回归审查 6 个阶段。核心能力是检测「git 不报行冲突但逻辑上互相破坏」的语义冲突，并在「不回滚原有逻辑」「能实现分支新增/修改逻辑」两个硬约束下解决行冲突，二者不可兼得时停下交人工确认。触发：把 main 对齐到分支 / 合流主干 / merge main 到当前分支 / align main / 同步主干修改 / 主干合流冲突处理。
version: 0.1.0
---

# qiq-alignmain — 把主干修改安全对齐到工作分支

## When to use

满足任一条件即启用：

- 用户希望把主干（`main` / `master` / `develop` 等长期分支）上的最新改动**合流到当前正在开发的分支**，让分支跟上主干。
- 用户提到关键词：**把 main 对齐到分支 / 合流主干 / merge main / align main / 同步主干 / 拉取主干最新代码 / 解决主干合流冲突**。
- 用户担心合流会引入冲突、回滚已有逻辑、或破坏线上功能，希望有可追溯、可回退、带逻辑冲突检查的合流过程。

不适用：

- 只是想新建分支或切分支 → 直接 `git switch`，不需要本 skill。
- 把分支合回主干 / 提交 MR / 发布上线 → 那是反向流程，本 skill 只负责「主干 → 分支」方向的对齐。
- 仓库没有可对齐的主干、或当前不在 git 仓库 → 先确认环境。

## 核心原则

1. **方向单一**：本 skill 只做 **主干 → 当前工作分支** 的合流对齐，绝不反向把工作分支推回主干。
2. **可回退优先**：任何破坏性 git 动作（merge / stash pop / reset）前，必须先记录可回退锚点（合流前 HEAD、stash 引用），并写入产物，保证随时能恢复到合流前状态。
3. **逻辑冲突 ≥ 行冲突**：git 不报冲突 **不等于** 没冲突。两边改了不同位置却互相破坏语义（改签名/删字段/改语义/重构）才是最危险的，必须主动检查并记录。
4. **行冲突解决的两条硬约束（不可违背）**：解决任何一处行冲突时，结果必须**同时**满足——① **不回滚已有逻辑**（主干带来的 + 分支已有的，二者的有效行为都要保留）；② **完整实现分支本次准备新增/修改的逻辑**。两者无法同时满足时 **停止并交人工确认**，禁止 AI 擅自二选一。
5. **存疑即停，不擅自发挥**：合流不是重构。禁止借合流之机改命名、删功能、做"顺手优化"；所有取舍必须显式记录并在存疑时交人工。
6. **可恢复**：所有中间产物落盘到**工作仓库根目录**下的 `.qiqskills/<分支名>/`，支持断点续传与事后追溯。

## 渐进披露阅读索引（按需加载）

主入口只放骨架，**细节按 Phase 加载对应 reference**，不要一次性灌进上下文：

| 阶段 | 必读 reference | 必读 template |
|---|---|---|
| Phase 0/1 确认分支 + 暂存 | `references/01-preflight.md` | `templates/ALIGN_PROGRESS.md` |
| Phase 2 逻辑冲突检查（核心） | `references/02-logical-conflict-check.md` | `templates/LOGICAL_CONFLICTS.md` |
| Phase 3/4 merge + 行冲突解决 | `references/03-merge-and-resolve.md` | `templates/CONFLICT_RESOLUTION.md` |
| Phase 5 合流后整体审查 | `references/04-post-merge-review.md` | `templates/POST_MERGE_REVIEW.md` |

辅助脚本：`scripts/collect_diffs.sh` —— 一把收集「主干侧 diff」「分支侧 diff」「双方共同改动文件」用于 Phase 2 逻辑冲突分析，token 高效。

## Workflow

整个流程按 6 个阶段顺序执行；**Phase 2 与 Phase 5 是 STOP & CONFIRM 关口**（逻辑冲突结论、合流后回归结论必须给用户确认），其余阶段连续执行并实时更新 `ALIGN_PROGRESS.md`。

```
Phase 0 确认工作分支 + 主干分支 + 仓库状态 + 建产物目录
   ↓
Phase 1 暂存未提交改动（stash/commit），记录可回退锚点
   ↓
Phase 2 ★合流前逻辑冲突检查与记录（STOP & CONFIRM）
   ↓
Phase 3 merge 主干（捕获 git 行冲突）
   ↓
Phase 4 行冲突逐处解决与记录（两条硬约束；冲突交人工）
   ↓
Phase 5 ★合流后整体审查：覆盖线上功能? 引入 bug?（STOP & CONFIRM）
```

### Phase 0 — 确认工作分支与主干

按 [@references/01-preflight.md](references/01-preflight.md) §0 执行：

- 确认 **工作分支**：默认 = 当前分支（`git branch --show-current`）；若用户另行指定则切换并复核。
- 确认 **主干分支**：默认探测 `main`，其次 `master`、`origin/HEAD`；多候选或不确定时向用户确认。
- `git fetch` 拉取主干最新远端状态（不自动 pull 工作分支）。
- 检查工作区状态、是否处于 rebase/merge 中途、是否 detached HEAD。
- 在工作仓库根目录建立产物目录 `.qiqskills/<分支名>/`，初始化 `ALIGN_PROGRESS.md`（基于 [@templates/ALIGN_PROGRESS.md](templates/ALIGN_PROGRESS.md)），记录合流前 HEAD（`git rev-parse HEAD`）作为**可回退锚点**。

### Phase 1 — 暂存未提交改动

按 [@references/01-preflight.md](references/01-preflight.md) §1 执行：

- 若工作区干净 → 记录"无需暂存"，跳过。
- 若有未提交改动 → 默认用 `git stash push -u -m "qiq-alignmain:<分支名>:<时间戳>"` 暂存（含未跟踪文件）；记录 stash 引用到 `ALIGN_PROGRESS.md`。用户偏好提交则改为新建一个 WIP commit，二选一须明确告知用户。
- **绝不**用 `git checkout -- .` / `git reset --hard` 等丢弃工作区的方式"清理"。

### Phase 2 — 合流前逻辑冲突检查（★STOP & CONFIRM）

按 [@references/02-logical-conflict-check.md](references/02-logical-conflict-check.md) 执行，这是本 skill 的核心价值：

1. 用 `scripts/collect_diffs.sh <主干> <merge-base>` 收集**主干侧改动**（merge-base→主干）与**分支侧改动**（merge-base→分支）。
2. 按 reference 中的「7 类语义冲突清单」逐类排查：即使 git 不会在这些位置报行冲突，两边改动是否**逻辑上互相破坏**（如主干改了函数签名/删了字段/改了某配置语义/重构了模块，而分支基于旧形态新增了调用方或逻辑）。
3. 产出 `.qiqskills/<分支名>/LOGICAL_CONFLICTS.md`（基于 [@templates/LOGICAL_CONFLICTS.md](templates/LOGICAL_CONFLICTS.md)），逐条登记：冲突点、双方改动、风险等级、预案（合流后如何修正）。
4. **STOP**：把逻辑冲突清单贴给用户确认，高风险项必须达成处理共识后才进入 Phase 3。

### Phase 3 — merge 主干

按 [@references/03-merge-and-resolve.md](references/03-merge-and-resolve.md) §3 执行：

- 执行 `git merge <主干>`（默认产生 merge commit，保留合流历史；不擅自改用 rebase 改写工作分支历史，除非用户明确要求）。
- 干净合入 → 进入 Phase 5（仍要做逻辑冲突预案的落地核对）。
- 出现行冲突 → `git status` 收集全部冲突文件清单，进入 Phase 4。

### Phase 4 — 行冲突逐处解决与记录

按 [@references/03-merge-and-resolve.md](references/03-merge-and-resolve.md) §4 执行，对每个冲突块（hunk）：

- 读懂 `<<<<<<< HEAD`（分支侧）/ `=======` / `>>>>>>> <主干>`（主干侧）双方意图。
- 在 **§核心原则 4 的两条硬约束**下给出合并结果：既保留主干带来的有效逻辑、又保留分支已有逻辑、且完整实现分支本次目标。
- 两条硬约束**无法同时满足**（例如主干删除了分支正要扩展的函数）→ 标记 `NEEDS-HUMAN`，**停下交人工确认**，不擅自取舍。
- 逐块记录到 `.qiqskills/<分支名>/CONFLICT_RESOLUTION.md`（基于 [@templates/CONFLICT_RESOLUTION.md](templates/CONFLICT_RESOLUTION.md)）：文件、冲突块、分支侧意图、主干侧意图、解决方案、是否满足两条硬约束、是否需人工。
- 所有冲突解决并通过基本校验后 `git add` 并完成 merge commit；存在 `NEEDS-HUMAN` 未决项则**不提交**，先交人工。

### Phase 5 — 合流后整体审查（★STOP & CONFIRM）

按 [@references/04-post-merge-review.md](references/04-post-merge-review.md) 执行：

- **回归 Phase 2 预案**：逐条核对 `LOGICAL_CONFLICTS.md` 中每个逻辑冲突是否已在合流结果中正确消化（很多语义冲突 git 不报错，必须人工/搜索核对）。
- **覆盖线上功能检查**：合流结果是否意外覆盖/回退了主干已有（即线上在跑）的功能或修复。
- **引入 bug 检查**：合流是否引入新的不一致（调用方/被调方签名、字段、错误码、配置、依赖版本不匹配等）；尽量跑构建/测试做客观验证。
- 产出 `.qiqskills/<分支名>/POST_MERGE_REVIEW.md`（基于 [@templates/POST_MERGE_REVIEW.md](templates/POST_MERGE_REVIEW.md)）。
- 提示用户：之前 stash 的改动是否需要 `git stash pop` 恢复（恢复后可能再次产生冲突，按 Phase 4 同样规则处理）。
- **STOP**：把审查结论交用户确认；存在未消化的高风险项不得宣告"对齐完成"。

## 状态与产物目录约定

**位置锚点（强制）**：所有读写以**用户工作仓库根目录**（调用 skill 时 shell 的 `pwd`）为基准，且必须是一个 git 仓库根。

所有中间产物固定写入 `.qiqskills/<分支名>/`（`<分支名>` 中的 `/` 替换为 `-`，避免建出多级目录）：

```
.qiqskills/<分支名>/
├── ALIGN_PROGRESS.md         # 进度面板 + 可回退锚点（合流前 HEAD / stash 引用）
├── LOGICAL_CONFLICTS.md      # Phase 2 逻辑冲突检查记录
├── CONFLICT_RESOLUTION.md    # Phase 4 行冲突逐块解决记录
└── POST_MERGE_REVIEW.md      # Phase 5 合流后整体审查记录
```

`.qiqskills/` 建议加入 `.gitignore`（除非用户希望把对齐记录一起提交）。

## 红线（Hard Rules — 违反即立即停止并向用户报告）

- ❌ **反向污染主干**：向主干 push、把工作分支 merge/rebase 进主干，或改写主干历史。
- ❌ **丢弃用户改动**：用 `reset --hard`、`checkout -- .`、`clean -fd` 等丢弃未提交改动；未提交改动一律走 Phase 1 暂存。
- ❌ **跳过逻辑冲突检查**：未产出并确认 `LOGICAL_CONFLICTS.md` 就直接 merge。
- ❌ **擅自二选一**：行冲突在两条硬约束下不可兼得时，AI 自行回滚一方逻辑而不交人工确认。
- ❌ **借合流搞重构**：在冲突解决/合流过程中改命名、删功能、做未要求的"优化"。
- ❌ **带未决项收尾**：存在 `NEEDS-HUMAN` 冲突或未消化高风险逻辑冲突时，提交 merge 或宣告"对齐完成"。
- ❌ **无回退锚点动手**：未先记录合流前 HEAD / stash 引用就执行 merge。

## Pitfalls

- **只信 git 不报冲突就放心** → 语义冲突 git 根本不报；Phase 2/Phase 5 必须主动核对。
- **stash 后忘记 pop** → Phase 5 必须提示用户处理被暂存的改动。
- **把 merge 改成 rebase 改写分支历史** → 默认 merge；rebase 需用户明确同意，且仍只动工作分支。
- **冲突解决时只保留一方** → 多数情况下双方逻辑都要保留，"二选一"是最后手段且要交人工。
- **跨多分支同时对齐** → 一次会话只对齐一个工作分支；多分支分别启动。
- **合流后不验证** → 至少跑构建/相关测试，把"引入 bug"从主观判断变成客观结论。

## Verification（交付前逐项核对）

- [ ] **Phase 0**：工作分支、主干分支已确认；`git fetch` 已执行；合流前 HEAD 已记录为回退锚点。
- [ ] **Phase 1**：未提交改动已安全暂存（stash 引用或 WIP commit 已记录），无任何丢弃式清理。
- [ ] **Phase 2**：`LOGICAL_CONFLICTS.md` 已产出，7 类语义冲突已逐类排查，已交用户确认。
- [ ] **Phase 3**：merge 已执行，行冲突文件清单已完整收集。
- [ ] **Phase 4**：`CONFLICT_RESOLUTION.md` 逐块记录；每块解决方案标注是否满足两条硬约束；所有 `NEEDS-HUMAN` 项均已交人工，无擅自二选一。
- [ ] **Phase 5**：`POST_MERGE_REVIEW.md` 已产出；Phase 2 逻辑冲突预案逐条核对消化；覆盖线上功能/引入 bug 两项均有结论；构建/测试结果已登记；stash 恢复事项已提示；已交用户确认。
