# Networking Guided First-Level Page 开发计划

## 步骤

- [x] 增加 Networking cockpit 源码测试，锁定原生 SwiftUI、三步英文引导、隐私提示、隐藏 prompt、生成式头像和两个社区名称。
- [x] 重写 `NetworkingCockpitView` 为三步式页面：生成 profile、绑定社区、查看消息线索。
- [x] 英文化 App 一级页面可见文案。
- [x] 移除一级页面上的 prompt 展示。
- [x] 用 `GeneratedFaceAvatar` 替换单字母头像表现。
- [x] 保留两个社区：`Know You Careers`、`Know You Friends`。
- [x] 运行不依赖 Xcode project 的 Swift typecheck。
- [x] 运行源码断言覆盖页面文案和禁用模式。
- [ ] 运行 focused XCTest。
- [ ] 运行完整 `xcodebuild test` 和 `xcodebuild build`。

## 当前验证状态

`xcodebuild` 当前被本机 Xcode 系统组件阻塞：`IDESimulatorFoundation` 无法加载 CoreSimulator，系统提示需要 `xcodebuild -runFirstLaunch`，但该命令在本机静默运行超过两分钟未返回。项目侧已用 `xcrun --sdk macosx swiftc -typecheck` 覆盖 Networking 相关 Swift 文件，并用源码断言覆盖 UI 结构要求。
