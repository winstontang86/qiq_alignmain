# 01 — Preflight：确认分支与安全暂存（Phase 0 / Phase 1）

本文覆盖合流前的环境确认与未提交改动的安全暂存。目标：在任何破坏性动作前，建立**清晰的对齐目标**和**可回退锚点**。

---

## §0 确认工作分支与主干

### 0.1 确认工作分支（对齐的目标分支）

- 默认工作分支 = 当前分支：
  ```bash
  git rev-parse --is-inside-work-tree   # 确认在 git 仓库内，否则停止并提示用户
  git branch --show-current             # 当前分支名；为空说明 detached HEAD
  ```
- 若结果为空（detached HEAD 或正处于 rebase/merge 中途）→ **停止**，向用户说明状态，让其先切到正常分支或处理完中途操作。
- 若用户显式指定了别的工作分支 → `git switch <branch>` 切过去，并复述"将把主干对齐到 `<branch>`"。

### 0.2 确认主干分支（被对齐进来的来源）

按优先级探测，**不确定就问用户**：

```bash
git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p'   # 远端默认分支
git branch -a | grep -E 'remotes/origin/(main|master|develop)$'      # 常见主干候选
```

- 命中唯一 `main` → 用 `main`；否则在 `master` / `develop` / `origin/HEAD` 中按用户确认选定。
- 记录主干的远端形态（通常对齐目标是 `origin/<主干>` 的最新状态，而非本地可能过期的同名分支）。

### 0.3 拉取主干最新状态

```bash
git fetch origin <主干> --prune       # 只更新远端引用，不改动工作分支
```

- 之后合流目标统一用 `origin/<主干>`（除非用户明确要对本地主干分支）。
- **不要**对工作分支执行 `git pull`（避免把工作分支也卷入意外合并）。

### 0.4 计算 merge-base（后续逻辑冲突检查的基准）

```bash
git merge-base HEAD origin/<主干>      # 共同祖先 commit，记为 <merge-base>
```

- merge-base 是判断"分支侧改了什么 / 主干侧改了什么"的分界点，Phase 2 强依赖它；`collect_diffs.sh` 省略第二参时会自动计算，此处无需单独落盘。

### 0.5 建立产物目录与回退锚点

- 产物目录名为 `<仓库名>-<分支名>`，其中：
  - `<仓库名>` 取工作仓库名：优先用 git remote 的仓库名（`basename -s .git "$(git remote get-url origin)"`），无 remote 时回落到仓库根目录名（`basename "$(git rev-parse --show-toplevel)"`）。
  - `<分支名>` 中的 `/`（如 `feature/x`）替换为 `-`（→ `feature-x`）；同理 `<仓库名>` 内若含 `/` 也替换为 `-`，避免建出多级目录。
  - 示例：仓库 `qiq_alignmain` + 分支 `feature/login` → `.qiqskills/qiq_alignmain-feature-login/`。
- 建目录并初始化进度面板（基于 `templates/ALIGN_PROGRESS.md`）：
  ```bash
  REPO="$(basename -s .git "$(git remote get-url origin 2>/dev/null)" 2>/dev/null)"
  [ -z "$REPO" ] && REPO="$(basename "$(git rev-parse --show-toplevel)")"
  BR="$(git branch --show-current | tr '/' '-')"
  mkdir -p ".qiqskills/${REPO}-${BR}"
  git rev-parse HEAD                    # 合流前 HEAD，写入 ALIGN_PROGRESS.md 作为回退锚点
  ```
- 回退锚点的意义：万一合流出错，可 `git merge --abort`（merge 中途）或 `git reset --hard <合流前HEAD>`（已生成 merge commit 且确认要放弃）回到原点。**这些回退动作只在用户明确要求放弃合流时执行。**

### 0.6 历史中间产物归档（首次写新产物前）

`.qiqskills/<仓库名>-<分支名>/` 可能因为同分支前一次对齐而残留旧产物（`ALIGN_PROGRESS.md` / `LOGICAL_CONFLICTS.md` / `CONFLICT_RESOLUTION.md` / `POST_MERGE_REVIEW.md`）。**新一次执行严禁直接覆盖**，必须先把历史产物搬入归档子目录，再写新产物。

判定与动作：

```bash
WORK_DIR=".qiqskills/${REPO}-${BR}"
TS="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_DIR="${WORK_DIR}/archive/${TS}"

shopt -s nullglob
old=( "$WORK_DIR"/ALIGN_PROGRESS.md \
      "$WORK_DIR"/LOGICAL_CONFLICTS.md \
      "$WORK_DIR"/CONFLICT_RESOLUTION.md \
      "$WORK_DIR"/POST_MERGE_REVIEW.md )
shopt -u nullglob

if [ ${#old[@]} -gt 0 ]; then
  mkdir -p "$ARCHIVE_DIR"
  mv "${old[@]}" "$ARCHIVE_DIR"/
  echo "归档历史中间产物 → $ARCHIVE_DIR"
fi
```

规则：

- 归档目录命名固定为 `archive/<YYYYMMDD-HHMMSS>/`，时间戳取本次执行启动时间，与 `ALIGN_PROGRESS.md` 的"启动时间"一致，方便回查。
- 仅归档 4 个标准中间产物文件；`archive/` 子目录本身、`.gitignore` 等其他文件原样保留。
- 已存在的 `archive/` 历史目录**不要清理、不要再次搬动**，保留逐次执行的全量历史。
- 归档完成后才生成新的 `ALIGN_PROGRESS.md`；并在新文件的"历史归档目录"字段回填本次 `archive/<时间戳>/` 路径，未发生归档则填 `无`。
- 若 `mv` 失败（权限/磁盘等），**停止**并向用户报告，不得在残留旧产物的目录下继续写新文件。

---

## §1 暂存未提交改动

### 1.1 判断工作区状态

```bash
git status --porcelain                 # 空 = 工作区干净
```

- 干净 → 在 `ALIGN_PROGRESS.md` 记"无需暂存"，直接进入 Phase 2。

### 1.2 默认方式：stash（推荐）

```bash
git stash push -u -m "qiq-alignmain:<仓库名>-<分支名>:<YYYYMMDD-HHMMSS>"
git stash list | head -1               # 确认 stash 引用（如 stash@{0}）
```

- `-u` 连未跟踪文件一起暂存，避免遗漏新文件。
- 把 stash 的 message 与引用写入 `ALIGN_PROGRESS.md`，Phase 5 据此提示恢复。
- 注意：`stash` 不暂存被 `.gitignore` 忽略的文件（一般无需暂存）；如有特殊忽略产物需保留，提示用户。

### 1.3 备选方式：WIP commit

用户偏好"用提交而非 stash"时：

```bash
git add -A
git commit -m "WIP: qiq-alignmain 合流前暂存（合流后可 reset 回退）"
```

- 记录该 WIP commit 的 hash；Phase 5 可提示用户用 `git reset --soft HEAD~1` 把 WIP 改动还原为工作区改动。
- 二选一必须**明确告知用户采用了哪种**，并写入进度面板。

### 1.4 同步当前分支远程更新（合入主干前）

在暂存完成后、进入 Phase 2 前，必须检查当前工作分支的远程是否有新内容。若远端已被其他人推送了新的 commit，直接 `merge origin/<主干>` 会导致不必要的冲突或逻辑混乱。应先同步当前分支的远程更新。

```bash
git fetch origin <当前分支> --prune         # 拉取当前分支远程的最新状态

# 检查本地是否落后于远程
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/<当前分支>)
if [ "$LOCAL" != "$REMOTE" ]; then
  echo "当前分支远程有更新，先合入远程内容"
  git merge origin/<当前分支> --no-edit      # 将远程更新合入本地
  # 如有冲突，按 §1.4.1 处理
fi
```

- 若 `LOCAL == REMOTE`（本地已是最新），记录"当前分支远程无更新"，直接进入 Phase 2。
- 若远程有新 commit 且合并无冲突，记录 merge commit 或 fast-forward 结果，进入 Phase 2。
- 若合并产生行冲突，按以下规则处理。

#### 1.4.1 远程同步冲突处理

远程同步冲突是本分支与远程同一分支之间的冲突，通常是多人协作导致。处理优先级：

1. **AI 可自行解决**：冲突内容明确、双方修改互不干扰，融合后写入 `ALIGN_PROGRESS.md` 记录。
2. **NEEDS-HUMAN**：冲突涉及相同区域、无法判断取舍、存在逻辑互斥 → 标记 `NEEDS-HUMAN`，**停止**并向用户说明冲突内容，等待裁决后再继续。

- 冲突记录必须写入 `ALIGN_PROGRESS.md` 的 "远程同步" 章节，包含冲突文件、冲突块数、解决方式。
- 远程同步冲突解决后，确认 `git status` 干净再进入 Phase 2。
- **绝不**在远程同步冲突未解决的情况下继续合入主干。

---

### 1.5 禁止动作

- ❌ `git reset --hard` / `git checkout -- .` / `git clean -fd` 等任何会**丢弃**未提交改动的命令。
- ❌ 在未记录回退锚点 / stash 引用前就推进到 merge。

---

## 完成本阶段的判定

- [ ] 确认在 git 仓库内，工作分支与主干分支已明确。
- [ ] `git fetch` 已执行，merge-base 已计算。
- [ ] 产物目录已建，合流前 HEAD 已记录为回退锚点。
- [ ] 旧的中间产物（如有）已搬入 `archive/<时间戳>/`，新产物未覆盖历史。
- [ ] 未提交改动已安全暂存（stash 引用或 WIP commit 已记录），或确认工作区干净。
- [ ] 当前分支远程更新已检查：若无更新则记录"无更新"；若有更新已合入，冲突已解决并记录。
