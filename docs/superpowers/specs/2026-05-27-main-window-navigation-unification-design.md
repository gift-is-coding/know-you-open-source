# Main Window Navigation Unification Design

## 背景

当前 `My Wiki` 入口在左侧栏使用独立按钮样式，并且主窗口在进入 My Wiki 时切换到另一套 workspace 结构。这会让右上角 engine selector 的位置感知变得不稳定，也会让 `My Wiki` 看起来不像 `Other Source` 和 `My Diary` 的同级入口。

## 目标

- `My Wiki`、`Other Source`、`My Diary` 必须是同一组左侧 root row，使用同一套字号、图标尺寸、行高和选中态。
- `My Wiki` 不再用单独的顶部按钮或独立 sidebar 样式呈现。
- 主窗口始终使用同一个 `NavigationSplitView`。选择左侧不同 root 只切换中间内容，不替换全局窗口结构。
- 右上角 engine selector 必须留在全局 toolbar 中，不随 `My Wiki` / `Other Source` / `My Diary` 切换而移动。
- `Other Source` 保持现有 source 管理入口语义；底层 route 名称可继续复用 `add-source`，但用户可见 root label 使用 `Other Source`。

## 非目标

- 不重做 engine selector 本身。
- 不调整 My Wiki pipeline、source catalog 或 ingest 语义。
- 不改变外部 source 文件树的层级规则。

## 验收

- 点击 `My Wiki` 后，左侧栏仍是同一个 sidebar；`My Wiki` 行与 `Other Source`、`My Diary` 样式一致。
- 点击 `My Wiki` 后，右上角 engine selector 仍固定在窗口 toolbar 的右侧。
- 点击 `Other Source` 或 `My Diary` 后，engine selector 不跳动、不变成内容区的一部分。
- 单元测试覆盖 root item presentation、selection action 和主窗口 workspace policy。
