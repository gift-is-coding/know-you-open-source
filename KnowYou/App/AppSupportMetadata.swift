import Foundation

struct AppSupportMetadata {
    static let twitterURL = URL(string: "https://x.com/TianfuW49629")!
    static let contactEmail = "cestlouiswu@gmail.com"
    static let emailURL = URL(string: "mailto:\(contactEmail)")!
    static let discordURL = URL(string: "https://discord.gg/ZrqF5jwQ")
    static let productTagline = "A local-first daily story for your workday on Mac."
    static let discordButtonTitle = "加入 Discord 社区"
    static let discordDescription = "适合讨论产品想法、反馈体验、分享你的日记工作流。"
    static let supportDescription = "隐私问题或不适合公开讨论的内容，请直接发邮件联系。"
    static let companyEnglishName = "Shanghai Erren Beiwu Software Co., Ltd."
    static let copyrightLine = "Copyright © 2026 Shanghai Erren Beiwu Software Co., Ltd. All rights reserved."
}

struct AppSupportDocument: Identifiable {
    let id: String
    let buttonTitle: String
    let title: String
    let body: String

    static let privacy = AppSupportDocument(
        id: "privacy",
        buttonTitle: "隐私政策",
        title: "隐私政策",
        body: """
        Know You 是一个本地优先的 macOS 应用。

        我们当前处理的数据主要来自这台 Mac 上的系统剪贴板和本机 Notification Center 数据库，以及事件的来源应用、采集时间、日期键等元数据。

        隐私过滤发生在内容持久化之前。这意味着明显敏感的内容不应以原文形式进入本地 SQLite，本地 Markdown 文件也不是原始上下文的无过滤转储。

        默认情况下，Know You 会把运行数据存放在当前 Mac 的本地目录中，包括：
        - ~/Library/Application Support/KnowYou/events.sqlite
        - ~/Library/Application Support/KnowYou/Vault

        外部总结器是可选增强，不是首次 onboarding 和首次生成故事的前置依赖。

        联系方式：
        - X / Twitter: https://x.com/TianfuW49629
        - Email: cestlouiswu@gmail.com
        """
    )

    static let terms = AppSupportDocument(
        id: "terms",
        buttonTitle: "使用条款",
        title: "使用条款",
        body: """
        Know You 按“现状”提供，不附带任何明示或暗示担保。

        你需要自行判断是否适合在自己的设备、工作环境和数据场景中使用 Know You，并自行负责审查本地保存的内容、保护自己的设备和账户安全，以及判断是否启用第三方总结器。

        如果你主动配置并使用第三方总结器或相关外部工具，你与这些第三方服务之间的关系受它们各自的条款和隐私政策约束。

        你不得将 Know You 用于任何违法用途，也不得借助该软件侵犯他人隐私、知识产权或其他合法权益。

        Copyright © 2026 Shanghai Erren Beiwu Software Co., Ltd. All rights reserved.
        """
    )

    static let community = AppSupportDocument(
        id: "community",
        buttonTitle: "社区说明",
        title: "社区说明",
        body: """
        Know You 当前主社区平台是 Discord，适合讨论产品想法、反馈体验、分享你的日记工作流。

        当前邀请链接：
        https://discord.gg/ZrqF5jwQ

        推荐频道包括：
        - #welcome
        - #announcements
        - #general
        - #show-your-story
        - #feedback
        - #bug-reports
        - #off-topic

        如果内容涉及隐私、敏感工作上下文或不适合公开披露的信息，请直接发邮件联系：cestlouiswu@gmail.com
        """
    )

    static let launchChecklist = AppSupportDocument(
        id: "launch-checklist",
        buttonTitle: "上线清单",
        title: "上线清单",
        body: """
        法律与文档
        - 隐私政策
        - 使用条款
        - 社区说明
        - 支持邮箱

        社区
        - Discord 服务器
        - 稳定邀请链接
        - #welcome 欢迎文案
        - 社区规则

        产品与分发
        - App 图标
        - 应用截图
        - 版本说明
        - 下载页或官网落地页

        macOS 发布准备
        - Developer ID 签名
        - notarization
        - 发布包验证
        - 首次安装说明
        - 权限说明截图
        """
    )
}
