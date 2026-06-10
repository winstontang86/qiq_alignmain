# qiq-alignmain

把主干（`main` / `master`）的最新修改**安全对齐（合流）到当前工作分支**的工程化 agent skill。

核心价值：不仅解决 git 行冲突，更主动检测「**git 不报行冲突、但双方改动逻辑上互相破坏**」的语义冲突，并在两条硬约束下解决冲突，存疑即停交人工。

## 定位

```
主干（线上/main 最新） ──┐
                        ├──[ qiq-alignmain 安全对齐 ]──→ 跟上主干、逻辑无损的工作分支
当前工作分支（在开发）  ──┘
```

只做 **主干 → 当前工作分支** 单一方向的合流，绝不反向把工作分支推回主干。

## 6 阶段流程

| Phase | 名称 | 说明 |
|---|---|---|
| 0 | 确认工作分支与主干 | 默认工作分支=当前分支；探测主干；`fetch`；算 merge-base；记录回退锚点 |
| 1 | 暂存未提交改动 | 默认 `git stash -u`（或 WIP commit），绝不丢弃工作区 |
| 2 ★ | 合流前逻辑冲突检查 | 按 7 类语义冲突清单逐类排查并记录，STOP & CONFIRM |
| 3 | merge 主干 | `git merge origin/<主干>`，捕获行冲突 |
| 4 | 行冲突解决与记录 | 两条硬约束下逐块解决；不可兼得交人工 |
| 5 ★ | 合流后整体审查 | 是否覆盖线上功能？是否引入 bug？逻辑冲突预案逐条核对，STOP & CONFIRM |

★ = STOP & CONFIRM 关口，需用户确认。

## 两条硬约束（行冲突解决的核心）

解决每一处冲突，结果必须**同时**满足：

- **① 不回滚已有逻辑**：主干侧带来的有效行为 + 分支侧原有的有效行为都保留。
- **② 实现分支本次目标**：分支这次准备新增/修改的逻辑完整保留。

二者**无法同时满足** → 标记 `NEEDS-HUMAN`，停下交人工裁决，禁止 AI 擅自二选一回滚任意一方。

## 七类语义冲突清单（Phase 2 排查对象）

1. 函数/方法签名变更　2. 数据结构/字段变更　3. 接口/契约语义变更　4. 行为/默认值/常量语义变更　5. 模块重构/搬迁/删除　6. 共享资源/全局状态/副作用　7. 依赖/构建/迁移脚本

这些点 git 合流通常**不报冲突**，必须主动搜索+阅读核对。

## 目录结构

```
qiq-alignmain/
├── SKILL.md                              # skill 主入口（6 阶段 + 红线 + 校验清单）
├── references/
│   ├── 01-preflight.md                   # Phase 0/1 确认分支 + 安全暂存 + 回退锚点
│   ├── 02-logical-conflict-check.md      # Phase 2 逻辑冲突检查（7 类清单·核心）
│   ├── 03-merge-and-resolve.md           # Phase 3/4 merge + 两条硬约束解冲突
│   └── 04-post-merge-review.md           # Phase 5 覆盖线上功能/引入 bug 审查
├── templates/
│   ├── ALIGN_PROGRESS.md                 # 进度面板 + 回退锚点
│   ├── LOGICAL_CONFLICTS.md              # 逻辑冲突检查记录
│   ├── CONFLICT_RESOLUTION.md            # 行冲突逐块解决记录
│   └── POST_MERGE_REVIEW.md              # 合流后整体审查记录
├── scripts/
│   ├── collect_diffs.sh                  # 只读收集双方 diff，供逻辑冲突分析
│   └── build.sh                          # skill 打包脚本
├── LICENSE
└── README.md
```

## 运行时产物

skill 在被对齐的项目仓库内固定使用 `.qiqskills/<仓库名>-<分支名>/` 目录存放运行时产物（`<仓库名>` 取 git remote 仓库名或仓库根目录名，`<分支名>` 与 `<仓库名>` 中的 `/` 替换为 `-`）：

```
.qiqskills/<仓库名>-<分支名>/
├── ALIGN_PROGRESS.md         # 进度面板 + 可回退锚点（合流前 HEAD / stash 引用）
├── LOGICAL_CONFLICTS.md      # Phase 2 逻辑冲突检查记录
├── CONFLICT_RESOLUTION.md    # Phase 4 行冲突逐块解决记录
└── POST_MERGE_REVIEW.md      # Phase 5 合流后整体审查记录
```

建议把 `.qiqskills/` 加入被对齐项目的 `.gitignore`（除非希望把对齐记录一起提交）。

## 触发词

- 把 main 对齐到分支 / 合流主干 / merge main 到当前分支
- align main / 同步主干修改 / 拉取主干最新代码 / 主干合流冲突处理

## 强约束摘要

完整清单见 [SKILL.md](SKILL.md) 红线区，关键 4 项：

- ❌ **反向污染主干**：向主干 push、把工作分支 merge/rebase 进主干、改写主干历史。
- ❌ **丢弃用户改动**：用 `reset --hard` / `checkout -- .` / `clean -fd` 清理未提交改动。
- ❌ **跳过逻辑冲突检查**：未产出并确认 `LOGICAL_CONFLICTS.md` 就直接 merge。
- ❌ **擅自二选一 / 带未决项收尾**：两条硬约束不可兼得时自行回滚一方而不交人工；存在 `NEEDS-HUMAN` 时仍提交或宣告"对齐完成"。

## 打包发布

把 skill 打包为可分发的 zip：

```bash
# 默认：版本号取自 SKILL.md frontmatter version，回落到 git describe / 日期戳
bash scripts/build.sh

# 显式指定版本号
VERSION=v0.1.0 bash scripts/build.sh

# 仅校验产物清单与内部链接，不实际打包
bash scripts/build.sh --no-zip
```

构建产物输出到 `dist/qiq-alignmain-<version>.zip`，解包后顶层为 `qiq-alignmain/`。每次构建都会清理 `dist/` 并重新生成。

## License

见 `LICENSE`。
