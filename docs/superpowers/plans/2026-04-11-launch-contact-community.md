# KnowYou 联系入口、社区与正式上线基础设施实现计划

> **给执行代理的说明：** 本计划默认在独立 worktree 中执行，按任务逐项勾选。除非用户明确要求英文，否则过程文档与说明统一使用中文。

**目标：** 为 KnowYou 同时补齐应用内联系/社区入口、仓库对外法律与社区文档，以及正式上线前的基础清单。

**架构：** 以现有 `SettingsView` 作为应用内承接点，新增一个静态但可点击的 `About & Community` 区域；以仓库 Markdown 文档作为当前法律与社区正文载体；通过文档常量与 UI 文案对齐，避免应用内外口径分裂。

**技术栈：** SwiftUI、AppKit `NSWorkspace`、XCTest、Markdown 文档、xcodebuild

---

### 任务 1：创建 worktree 并验证隔离基线

**文件：**
- 修改：`.gitignore`（仅当 `.worktrees` 尚未被忽略时）
- 使用：`.worktrees/`

- [ ] **步骤 1：确认 worktree 目录和忽略规则**

运行：
```bash
git check-ignore -q .worktrees || echo NOT_IGNORED
ls -d .worktrees
```

预期：`.worktrees` 存在，且没有输出 `NOT_IGNORED`。

- [ ] **步骤 2：如果未忽略，则补上忽略规则**

将 `.gitignore` 补成至少包含：
```gitignore
.worktrees/
```

然后运行：
```bash
git add .gitignore
git commit -m "chore: ignore local worktrees"
```

预期：成功提交，仅在缺失忽略规则时执行。

- [ ] **步骤 3：创建独立 worktree**

运行：
```bash
git worktree add .worktrees/launch-contact-community -b feat/launch-contact-community
```

预期：生成新目录 `.worktrees/launch-contact-community`，并切到新分支 `feat/launch-contact-community`。

- [ ] **步骤 4：验证工程可在新 worktree 中读取**

运行：
```bash
cd .worktrees/launch-contact-community
xcodebuild -list -project KnowYou.xcodeproj
```

预期：输出包含 `KnowYou` scheme。

### 任务 2：先写失败测试，锁定 Settings 新区块的内容契约

**文件：**
- 创建：`KnowYouTests/SettingsMetadataTests.swift`
- 参考：`KnowYou/UI/Settings/SettingsView.swift`

- [ ] **步骤 1：写失败测试，定义联系与法律元数据**

创建测试文件：
```swift
import XCTest
@testable import KnowYou

final class SettingsMetadataTests: XCTestCase {
    func testAppSupportMetadataMatchesPublicContactContract() {
        XCTAssertEqual(AppSupportMetadata.twitterURL.absoluteString, "https://x.com/TianfuW49629")
        XCTAssertEqual(AppSupportMetadata.contactEmail, "cestlouiswu@gmail.com")
        XCTAssertEqual(AppSupportMetadata.companyEnglishName, "Shanghai Two-Person Beiwu Software Co., Ltd.")
        XCTAssertEqual(
            AppSupportMetadata.copyrightLine,
            "Copyright © 2026 Shanghai Two-Person Beiwu Software Co., Ltd. All rights reserved."
        )
    }

    func testDocumentLinksExposePrivacyTermsCommunityAndLaunchChecklist() {
        XCTAssertTrue(AppSupportMetadata.privacyDocumentName.hasSuffix("PRIVACY.md"))
        XCTAssertTrue(AppSupportMetadata.termsDocumentName.hasSuffix("TERMS.md"))
        XCTAssertTrue(AppSupportMetadata.communityDocumentName.hasSuffix("COMMUNITY.md"))
        XCTAssertTrue(AppSupportMetadata.launchChecklistDocumentName.hasSuffix("LAUNCH-CHECKLIST.md"))
    }
}
```

- [ ] **步骤 2：运行新测试，确认当前失败**

运行：
```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SettingsMetadataTests
```

预期：FAIL，提示 `AppSupportMetadata` 尚未定义。

- [ ] **步骤 3：实现最小元数据类型**

创建一个新文件，建议内容：
```swift
import Foundation

struct AppSupportMetadata {
    static let twitterURL = URL(string: "https://x.com/TianfuW49629")!
    static let contactEmail = "cestlouiswu@gmail.com"
    static let discordURL: URL? = nil
    static let companyEnglishName = "Shanghai Two-Person Beiwu Software Co., Ltd."
    static let copyrightLine = "Copyright © 2026 Shanghai Two-Person Beiwu Software Co., Ltd. All rights reserved."

    static let privacyDocumentName = "PRIVACY.md"
    static let termsDocumentName = "TERMS.md"
    static let communityDocumentName = "COMMUNITY.md"
    static let launchChecklistDocumentName = "LAUNCH-CHECKLIST.md"
}
```

- [ ] **步骤 4：重跑测试，确认通过**

运行：
```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SettingsMetadataTests
```

预期：PASS。

- [ ] **步骤 5：提交这一小步**

运行：
```bash
git add KnowYouTests/SettingsMetadataTests.swift KnowYou/App/AppSupportMetadata.swift
git commit -m "test: lock app support metadata contract"
```

### 任务 3：实现 Settings 的 About & Community 区域

**文件：**
- 修改：`KnowYou/UI/Settings/SettingsView.swift`
- 依赖：`KnowYou/App/AppSupportMetadata.swift`
- 测试：`KnowYouTests/SettingsMetadataTests.swift`

- [ ] **步骤 1：补充失败测试，锁定文案与降级行为**

向 `SettingsMetadataTests.swift` 追加：
```swift
func testDiscordStatusCopyFallsBackWhenInviteLinkIsMissing() {
    XCTAssertEqual(AppSupportMetadata.discordButtonTitle, "Discord 社区入口即将提供")
    XCTAssertEqual(AppSupportMetadata.discordDescription, "适合讨论产品想法、反馈体验、分享你的日记工作流。")
}
```

- [ ] **步骤 2：运行测试，确认失败**

运行：
```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SettingsMetadataTests
```

预期：FAIL，提示新增静态字段不存在。

- [ ] **步骤 3：补充元数据并实现 Settings 区域**

在 `AppSupportMetadata` 中补充：
```swift
static let productTagline = "A local-first daily story for your workday on Mac."
static let discordButtonTitle = "Discord 社区入口即将提供"
static let discordDescription = "适合讨论产品想法、反馈体验、分享你的日记工作流。"
```

在 `SettingsView.swift` 中新增一个 section，结构接近：
```swift
Section("About & Community") {
    VStack(alignment: .leading, spacing: 10) {
        Text("KnowYou")
            .font(.headline)
        Text(AppSupportMetadata.productTagline)
            .font(.callout)
            .foregroundStyle(.secondary)

        Button("关注 X / Twitter") {
            NSWorkspace.shared.open(AppSupportMetadata.twitterURL)
        }

        Button("发送邮件") {
            let url = URL(string: "mailto:\(AppSupportMetadata.contactEmail)")!
            NSWorkspace.shared.open(url)
        }

        if let discordURL = AppSupportMetadata.discordURL {
            Button("加入 Discord 社区") {
                NSWorkspace.shared.open(discordURL)
            }
        } else {
            Text(AppSupportMetadata.discordButtonTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Text(AppSupportMetadata.discordDescription)
            .font(.caption)
            .foregroundStyle(.secondary)

        Text(AppSupportMetadata.copyrightLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}
```

- [ ] **步骤 4：跑测试确认元数据与编译通过**

运行：
```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SettingsMetadataTests
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

预期：测试通过，工程成功编译。

- [ ] **步骤 5：提交 UI 小步**

运行：
```bash
git add KnowYou/UI/Settings/SettingsView.swift KnowYou/App/AppSupportMetadata.swift KnowYouTests/SettingsMetadataTests.swift
git commit -m "feat: add settings about and community section"
```

### 任务 4：补齐 README 与四份对外文档

**文件：**
- 修改：`README.md`
- 创建：`PRIVACY.md`
- 创建：`TERMS.md`
- 创建：`COMMUNITY.md`
- 创建：`LAUNCH-CHECKLIST.md`

- [ ] **步骤 1：写 README 新段落**

将 README 追加以下结构：
```md
## Contact

- X / Twitter: https://x.com/TianfuW49629
- Email: cestlouiswu@gmail.com

## Community

Discord is the primary community for KnowYou users and enthusiasts.
The server structure, rules, and launch checklist live in `COMMUNITY.md`.

## Privacy

KnowYou is local-first. Privacy boundaries and data flow are documented in `PRIVACY.md`.

## Support

Use email for private issues and account-sensitive questions.
Use the community for product discussion and feature feedback.
```

- [ ] **步骤 2：创建 `PRIVACY.md`**

写入至少包含以下结构：
```md
# KnowYou 隐私政策

## 我们收集什么
## 数据来源
## 隐私过滤发生在什么时候
## 数据默认存放位置
## 第三方总结器说明
## 你的控制权
## 联系方式
```

正文必须与当前架构一致：
- 剪贴板与通知为本机信号源
- 过滤先于持久化
- 默认本地存储
- 外部总结器为可选增强

- [ ] **步骤 3：创建 `TERMS.md`**

写入至少包含以下结构：
```md
# KnowYou 使用条款

## 软件提供方式
## 用户责任
## 第三方服务
## 禁止用途
## 责任限制
## 联系方式
```

正文要包含版权主体：
```md
Copyright © 2026 Shanghai Two-Person Beiwu Software Co., Ltd. All rights reserved.
```

- [ ] **步骤 4：创建 `COMMUNITY.md`**

写入至少包含以下结构：
```md
# KnowYou Community

## 社区定位
## Discord 频道建议
## 基本规则
## 如何反馈问题
## 何时发邮件而不是公开讨论
```

并明确频道：
- `#welcome`
- `#announcements`
- `#general`
- `#show-your-story`
- `#feedback`
- `#bug-reports`
- `#off-topic`

- [ ] **步骤 5：创建 `LAUNCH-CHECKLIST.md`**

写入至少包含以下清单段落：
```md
# KnowYou 正式上线检查清单

## 法律与文档
- [ ] 隐私政策
- [ ] 使用条款
- [ ] 支持邮箱

## 社区
- [ ] Discord 服务器已创建
- [ ] 稳定邀请链接已生成
- [ ] 欢迎文案与规则已发布

## 分发
- [ ] App 图标
- [ ] 截图
- [ ] 版本说明
- [ ] 签名
- [ ] notarization

## 支持
- [ ] FAQ / 已知问题
- [ ] bug 反馈入口
```

- [ ] **步骤 6：提交文档小步**

运行：
```bash
git add README.md PRIVACY.md TERMS.md COMMUNITY.md LAUNCH-CHECKLIST.md
git commit -m "docs: add launch legal and community documents"
```

### 任务 5：同步 requirements 与 architecture 文档

**文件：**
- 修改：`docs/requirements-spec.md`
- 修改：`docs/architecture.md`

- [ ] **步骤 1：更新 requirements**

在合适章节补充要求，至少表达这些事实：
```md
- Settings 页面必须提供作者联系与社区入口
- 产品必须展示 X/Twitter、邮箱与版权主体
- 仓库必须提供隐私政策、使用条款与社区说明文档
- Discord 是当前主社区形态
```

- [ ] **步骤 2：更新 architecture**

在界面层或运行时入口章节补充：
```md
- Settings 当前除了状态与配置，还承载 About & Community 区域
- About & Community 用于打开外部联系入口并展示法律摘要
- 完整法律与社区正文当前由仓库 Markdown 文档承载
```

- [ ] **步骤 3：校对两份文档与实际实现口径一致**

运行：
```bash
rg -n "Discord|隐私政策|使用条款|About & Community|X/Twitter|邮箱" docs/requirements-spec.md docs/architecture.md README.md PRIVACY.md TERMS.md COMMUNITY.md
```

预期：所有术语与当前实现一致，没有互相冲突的说法。

- [ ] **步骤 4：提交文档同步小步**

运行：
```bash
git add docs/requirements-spec.md docs/architecture.md
git commit -m "docs: sync product docs for launch support surfaces"
```

### 任务 6：完整验证并准备交付说明

**文件：**
- 检查：整个 worktree 改动

- [ ] **步骤 1：运行聚焦测试**

运行：
```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SettingsMetadataTests -only-testing:KnowYouTests/OnboardingContentTests
```

预期：PASS。

- [ ] **步骤 2：运行全量测试**

运行：
```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
```

预期：PASS。

- [ ] **步骤 3：运行全量构建**

运行：
```bash
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

预期：BUILD SUCCEEDED。

- [ ] **步骤 4：检查 git diff 与最终文件集**

运行：
```bash
git status --short
git diff --stat
```

预期：仅包含本次任务相关文件。

- [ ] **步骤 5：整理交付说明**

最终说明要覆盖：
```text
1. 应用内新增了什么
2. 新增了哪些文档
3. Discord 还差哪一步需要你手动完成
4. 运行了哪些测试与构建验证
```

