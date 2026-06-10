# 03 — merge 主干与行冲突解决（Phase 3 / Phase 4）

本文覆盖实际执行 merge 以及在两条硬约束下逐块解决 git 行冲突。

---

## §3 merge 主干

### 3.1 执行 merge

默认采用普通 merge（保留合流历史，产生 merge commit）：

```bash
git merge origin/<主干>
```

- **默认不用 rebase**：rebase 会改写工作分支历史，仅在用户明确要求"用 rebase 对齐"时才用，且仍只动工作分支、绝不动主干。
- 若仓库约定 `--no-ff` / squash 等策略，遵循用户/仓库约定。

### 3.2 判定结果

- **Already up to date** → 主干无新东西，确认 merge-base 是否就是主干 HEAD；告知用户无需对齐。
- **干净合入（无 CONFLICT 提示）** → 跳过 Phase 4，但**仍需进入 Phase 5**，因为干净合入恰恰是语义冲突的高发场景（git 没报 ≠ 没问题）。
- **出现 `CONFLICT`** → 收集全部冲突清单，进入 Phase 4：
  ```bash
  git status                                  # 看 "Unmerged paths"
  git diff --name-only --diff-filter=U         # 仅列出冲突文件
  ```

### 3.3 中途回退手段（仅用户要求放弃时）

```bash
git merge --abort        # 放弃本次 merge，回到合流前状态（merge 进行中）
```

---

## §4 行冲突逐块解决

### 4.1 两条硬约束（解决每一处冲突都必须满足）

> **约束 ①｜不回滚已有逻辑**：合并结果必须同时保留——主干侧本次带来的有效行为 + 分支侧原本已实现的有效行为。任何一方的有效逻辑都不能因为"选了另一方"而消失。
>
> **约束 ②｜实现分支本次目标**：合并结果必须完整保留分支这次开发准备新增/修改的逻辑意图。
>
> 二者**无法同时满足** → 标记 `NEEDS-HUMAN`，停下交人工，**禁止 AI 擅自二选一回滚任意一方**。

### 4.2 解析冲突块

冲突标记的含义（在工作分支上执行 merge 时）：

```
<<<<<<< HEAD
（分支侧 / ours：你当前分支的内容）
=======
（主干侧 / theirs：origin/<主干> 的内容）
>>>>>>> origin/<主干>
```

辅助查看双方原始意图：

```bash
git log --oneline <merge-base>..HEAD -- <file>           # 分支侧为何这么改
git log --oneline <merge-base>..origin/<主干> -- <file>   # 主干侧为何这么改
git diff <merge-base> HEAD -- <file>
git diff <merge-base> origin/<主干> -- <file>
```

### 4.3 解决策略（按优先级）

1. **融合双方（首选）**：两边改的是不同关注点 → 把两边逻辑都纳入，组织成同时生效的代码（满足 ① 和 ②）。
2. **以新形态承载旧意图**：主干重构了结构，分支的新增逻辑要**适配到主干新结构上重写**（而不是把主干结构改回旧的）——这既不回滚主干（①），又实现分支目标（②）。
3. **NEEDS-HUMAN（最后手段）**：双方逻辑在同一处真正互斥，无法同时成立（例：主干删除了分支正要扩展的函数 / 双方对同一行为给出相反定义）→ 停下，向用户清楚陈述"保留 A 则丢 B，保留 B 则丢 A"，交人工裁决。

### 4.4 禁止动作

- ❌ 图省事用 `git checkout --ours <file>` / `--theirs <file>` 整文件取一方（几乎必然违反约束 ① 或 ②）；如确需，必须逐块确认且记录理由。
- ❌ 借冲突解决删除"看起来没用"的代码、改命名、做未要求的优化。
- ❌ 把 `NEEDS-HUMAN` 项自行拍板后继续提交。

### 4.5 逐块记录

每个冲突块在 `.qiqskills/<仓库名>-<分支名>/CONFLICT_RESOLUTION.md` 登记（基于 template）：文件、冲突块定位、分支侧意图、主干侧意图、采用的解决策略、解决后代码摘要、是否满足约束①、是否满足约束②、是否 `NEEDS-HUMAN`。

### 4.6 收尾

- 解决完一处即移除冲突标记；全部解决后做基本校验（语法/构建/受影响测试）。
- 无 `NEEDS-HUMAN` 未决项时：
  ```bash
  git add <已解决文件...>
  git diff --name-only --diff-filter=U     # 必须为空才可提交
  git commit                                # 完成 merge commit（保留默认 merge message 或补充说明）
  ```
- 存在 `NEEDS-HUMAN` → **不提交**，把待裁决项交用户；得到决定后再回到本节继续。

---

## 完成本阶段的判定

- [ ] merge 已执行，结果（up-to-date / 干净 / 冲突）已判定。
- [ ] 每个冲突块都已记录，且标注是否满足两条硬约束。
- [ ] 所有 `git checkout --ours/--theirs` 整文件取舍（如有）均有逐块理由。
- [ ] 无 `NEEDS-HUMAN` 残留才提交 merge；否则已交人工。
