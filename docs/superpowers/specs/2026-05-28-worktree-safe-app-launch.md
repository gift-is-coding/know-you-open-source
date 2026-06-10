# Worktree-safe App Launch 规格

## 背景

开发期会同时打开多个 KnowYou worktree。当前 dev 启动脚本使用全局 `pkill` 和全局清理 DerivedData 中的 `KnowYou.app`，会误伤其他 worktree 正在运行或刚构建的 app。

## 目标

- 启动当前 worktree 的 app 时，只处理当前 worktree 自己的 dev build，不终止其他 worktree 的 KnowYou。
- App 右下角 build badge 必须显示当前 branch 或 worktree 名称，方便区分当前打开的是哪个分支。
- 构建元数据仍然是 bundle 内静态文件，运行时不执行 git 命令。

## 验收

- `scripts/run-dev-app.sh` 不得包含全局 `pkill -f '/KnowYou.app/Contents/MacOS/KnowYou'`。
- `scripts/run-dev-app.sh` 不得删除 `~/Library/Developer/Xcode/DerivedData` 下所有 `KnowYou.app`。
- `scripts/run-dev-app.sh` 必须用当前 worktree 的 `.derived-data/dev/.../KnowYou.app` 作为唯一进程匹配和清理边界。
- `BuildMetadata.json` 包含 `gitBranch` 和 `worktreeName`。
- `AppBuildMetadata.badgeText` 在 branch/worktree 可用时显示它们，并在缺失时安全回退。
