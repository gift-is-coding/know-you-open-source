# 日记分享 UX 修正计划

**目标：** 修正第一版分享功能的英文一致性、预览反馈、长内容截断、划选分享弹窗和可见脱敏问题，让分享流程更适合真实社群传播。

## 任务清单

- [x] 先更新分享 presentation、renderer、redactor 的测试，覆盖英文 UI、动态画布和可见遮挡块。
- [x] 统一分享相关文案为英文。
- [x] 把顶部分享和右键分享统一到同一个 popover 状态，并保证打开时默认勾选脱敏。
- [x] 在 popover 里增加当前图片预览。
- [x] 把分享图片 renderer 改为按正文高度动态扩展。
- [x] 强化 `DiaryShareRedactor`，用明显遮挡块替换敏感片段。
- [x] 跑 targeted tests、完整 test/build 和视觉验证。
