#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${1:-$HOME/Library/Application Support/KnowYou}"
DB_PATH="$ROOT_DIR/events.sqlite"
VAULT_DIR="$ROOT_DIR/Vault"

mkdir -p "$VAULT_DIR"

sqlite3 "$DB_PATH" <<'SQL'
CREATE TABLE IF NOT EXISTS events (
    id TEXT PRIMARY KEY,
    sourceType TEXT NOT NULL,
    sourceApp TEXT NOT NULL,
    capturedAt DATETIME NOT NULL,
    dayKey TEXT NOT NULL,
    text TEXT,
    auditText TEXT,
    privacyAction TEXT NOT NULL,
    contentHash TEXT NOT NULL UNIQUE
);

DELETE FROM events WHERE dayKey IN ('2026-04-04', '2026-04-05', '2026-04-06');

INSERT INTO events (id, sourceType, sourceApp, capturedAt, dayKey, text, auditText, privacyAction, contentHash) VALUES
('A4000000-0000-4000-8000-000000000001', 'notification', 'Slack',    '2026-04-04 08:52:00', '2026-04-04', '9 点 standup，今天把 onboarding preview 和 diary reader 的顺序定下来。', NULL, 'keep', 'demo-2026-04-04-01'),
('A4000000-0000-4000-8000-000000000002', 'clipboard',    'Notes',    '2026-04-04 09:06:00', '2026-04-04', '先让用户看到 diary，再解释权限；第一印象应该是结果，不是设置项。', NULL, 'keep', 'demo-2026-04-04-02'),
('A4000000-0000-4000-8000-000000000003', 'clipboard',    'Safari',   '2026-04-04 09:28:00', '2026-04-04', 'SwiftUI FocusState list detail keyboard navigation macOS', NULL, 'keep', 'demo-2026-04-04-03'),
('A4000000-0000-4000-8000-000000000004', 'clipboard',    'Figma',    '2026-04-04 09:57:00', '2026-04-04', 'reader 草图：左侧日期窄一些，中间像笔记页，右侧 detail 保持稳定宽度。', NULL, 'keep', 'demo-2026-04-04-04'),
('A4000000-0000-4000-8000-000000000005', 'clipboard',    'Xcode',    '2026-04-04 10:31:00', '2026-04-04', '把 diary header 的日期层级提上来，刷新按钮收进右上角。', NULL, 'keep', 'demo-2026-04-04-05'),
('A4000000-0000-4000-8000-000000000006', 'clipboard',    'Terminal', '2026-04-04 11:12:00', '2026-04-04', 'xcodebuild test -scheme KnowYou -destination ''platform=macOS'' -only-testing:KnowYouTests/MainWindowViewModelTests', NULL, 'keep', 'demo-2026-04-04-06'),
('A4000000-0000-4000-8000-000000000007', 'notification', 'Mail',     '2026-04-04 12:48:00', '2026-04-04', '反馈：detail column 宽度不要跟内容一起跳，读的时候会分心。', NULL, 'keep', 'demo-2026-04-04-07'),
('A4000000-0000-4000-8000-000000000008', 'clipboard',    'Safari',   '2026-04-04 13:26:00', '2026-04-04', 'Markdown typography readable long-form notes macOS app', NULL, 'keep', 'demo-2026-04-04-08'),
('A4000000-0000-4000-8000-000000000009', 'clipboard',    'Xcode',    '2026-04-04 14:11:00', '2026-04-04', '记住每一天上次选中的 paragraph，重新进入时恢复那个位置。', NULL, 'keep', 'demo-2026-04-04-09'),
('A4000000-0000-4000-8000-000000000010', 'clipboard',    'Terminal', '2026-04-04 15:03:00', '2026-04-04', 'xcodebuild build -scheme KnowYou -destination ''platform=macOS''', NULL, 'keep', 'demo-2026-04-04-10'),
('A4000000-0000-4000-8000-000000000011', 'clipboard',    'Ghostty',  '2026-04-04 17:42:00', '2026-04-04', 'git commit -m ''feat: polish diary reader spacing and header''', NULL, 'keep', 'demo-2026-04-04-11'),
('A4000000-0000-4000-8000-000000000012', 'clipboard',    'Notes',    '2026-04-04 20:16:00', '2026-04-04', '明天继续：验证历史日期刷新、再检查 onboarding preview 的故事感。', NULL, 'keep', 'demo-2026-04-04-12'),

('A5000000-0000-4000-8000-000000000001', 'notification', 'Slack',    '2026-04-05 08:58:00', '2026-04-05', 'Standup today: testing, concurrency, and Beta invites. Version notes need to be ready before tonight.', NULL, 'keep', 'demo-2026-04-05-01'),
('A5000000-0000-4000-8000-000000000002', 'clipboard',    'Safari',   '2026-04-05 09:19:00', '2026-04-05', 'Swift Concurrency: Task async/await actor isolation on MainActor', NULL, 'keep', 'demo-2026-04-05-02'),
('A5000000-0000-4000-8000-000000000003', 'clipboard',    'Notes',    '2026-04-05 09:46:00', '2026-04-05', 'Split AppState from automation responsibilities so onboarding does not interfere with the real capture pipeline.', NULL, 'keep', 'demo-2026-04-05-03'),
('A5000000-0000-4000-8000-000000000004', 'clipboard',    'Xcode',    '2026-04-05 10:21:00', '2026-04-05', 'Add a historical-date test for refreshSelectedDay so it never triggers notification import by mistake.', NULL, 'keep', 'demo-2026-04-05-04'),
('A5000000-0000-4000-8000-000000000005', 'clipboard',    'Terminal', '2026-04-05 11:07:00', '2026-04-05', 'xcodebuild test -scheme KnowYou -destination ''platform=macOS'' -only-testing:KnowYouTests/MainWindowViewModelTests', NULL, 'keep', 'demo-2026-04-05-05'),
('A5000000-0000-4000-8000-000000000006', 'clipboard',    'Safari',   '2026-04-05 12:15:00', '2026-04-05', 'GRDB migration and SQLite app state persistence patterns', NULL, 'keep', 'demo-2026-04-05-06'),
('A5000000-0000-4000-8000-000000000007', 'clipboard',    'Xcode',    '2026-04-05 13:44:00', '2026-04-05', 'Tighten the refresh status copy so it feels lighter and less like a utility banner.', NULL, 'keep', 'demo-2026-04-05-07'),
('A5000000-0000-4000-8000-000000000008', 'notification', 'Mail',     '2026-04-05 15:09:00', '2026-04-05', 'A new TestFlight build is available. Invite the Beta group for this round of experience testing.', NULL, 'keep', 'demo-2026-04-05-08'),
('A5000000-0000-4000-8000-000000000009', 'clipboard',    'Notes',    '2026-04-05 16:02:00', '2026-04-05', 'Beta checklist: read the story, switch dates, inspect detail, manually refresh today.', NULL, 'keep', 'demo-2026-04-05-09'),
('A5000000-0000-4000-8000-000000000010', 'clipboard',    'Terminal', '2026-04-05 17:18:00', '2026-04-05', 'brew upgrade grdb && pod repo update', NULL, 'keep', 'demo-2026-04-05-10'),
('A5000000-0000-4000-8000-000000000011', 'clipboard',    'Xcode',    '2026-04-05 19:06:00', '2026-04-05', 'Make summarizer setup feel optional and additive instead of blocking the onboarding flow.', NULL, 'keep', 'demo-2026-04-05-11'),
('A5000000-0000-4000-8000-000000000012', 'clipboard',    'Notes',    '2026-04-05 21:12:00', '2026-04-05', 'Today mostly clarified the boundary between testing, copy, and automation. Tomorrow is for CI and investor materials.', NULL, 'keep', 'demo-2026-04-05-12'),

('A6000000-0000-4000-8000-000000000001', 'notification', 'Calendar', '2026-04-06 08:41:00', '2026-04-06', '10 点设计同步，13 点投资人视频通话。', NULL, 'keep', 'demo-2026-04-06-01'),
('A6000000-0000-4000-8000-000000000002', 'clipboard',    'Figma',    '2026-04-06 09:03:00', '2026-04-06', '主色从 #2563EB 收到 #1D4ED8，正文背景再暖一点，层级更稳。', NULL, 'keep', 'demo-2026-04-06-02'),
('A6000000-0000-4000-8000-000000000003', 'notification', 'Slack',    '2026-04-06 09:37:00', '2026-04-06', 'CI/CD 流水线失败：测试超时，需要排查。', NULL, 'keep', 'demo-2026-04-06-03'),
('A6000000-0000-4000-8000-000000000004', 'clipboard',    'Safari',   '2026-04-06 10:02:00', '2026-04-06', 'xcodebuild test timeout diagnostics macOS CI', NULL, 'keep', 'demo-2026-04-06-04'),
('A6000000-0000-4000-8000-000000000005', 'clipboard',    'Xcode',    '2026-04-06 10:46:00', '2026-04-06', '@MainActor final class AppState: ObservableObject', NULL, 'keep', 'demo-2026-04-06-05'),
('A6000000-0000-4000-8000-000000000006', 'clipboard',    'Terminal', '2026-04-06 11:18:00', '2026-04-06', 'xcodebuild test -scheme KnowYou -destination ''platform=macOS'' -only-testing:KnowYouTests/MainWindowViewModelTests', NULL, 'keep', 'demo-2026-04-06-06'),
('A6000000-0000-4000-8000-000000000007', 'clipboard',    'Notes',    '2026-04-06 12:06:00', '2026-04-06', 'Investor call talking points: local-first, story-first, evidence-linked reader, privacy boundary.', NULL, 'keep', 'demo-2026-04-06-07'),
('A6000000-0000-4000-8000-000000000008', 'notification', 'Calendar', '2026-04-06 13:00:00', '2026-04-06', '与投资人视频通话 下午 1 点。', NULL, 'keep', 'demo-2026-04-06-08'),
('A6000000-0000-4000-8000-000000000009', 'clipboard',    'Safari',   '2026-04-06 14:22:00', '2026-04-06', 'daily journal product onboarding benchmark desktop app', NULL, 'keep', 'demo-2026-04-06-09'),
('A6000000-0000-4000-8000-000000000010', 'notification', 'Mail',     '2026-04-06 15:11:00', '2026-04-06', '跟进：请补一页 MVP 核心指标和近期验证计划。', NULL, 'keep', 'demo-2026-04-06-10'),
('A6000000-0000-4000-8000-000000000011', 'clipboard',    'Notes',    '2026-04-06 15:38:00', '2026-04-06', 'MVP 核心指标：DAU > 100，次日留存 > 40%，首周至少 10 位真实测试者。', NULL, 'keep', 'demo-2026-04-06-11'),
('A6000000-0000-4000-8000-000000000012', 'clipboard',    'Xcode',    '2026-04-06 16:27:00', '2026-04-06', '把 automation status 和 refresh status 文案统一，减少面板感。', NULL, 'keep', 'demo-2026-04-06-12'),
('A6000000-0000-4000-8000-000000000013', 'clipboard',    'Terminal', '2026-04-06 17:16:00', '2026-04-06', 'xcodebuild build -scheme KnowYou -destination ''platform=macOS''', NULL, 'keep', 'demo-2026-04-06-13'),
('A6000000-0000-4000-8000-000000000014', 'notification', 'Slack',    '2026-04-06 18:34:00', '2026-04-06', '设计反馈已看：当前配色更稳，detail 宽度固定后阅读节奏明显好一些。', NULL, 'keep', 'demo-2026-04-06-14'),
('A6000000-0000-4000-8000-000000000015', 'clipboard',    'Notes',    '2026-04-06 20:08:00', '2026-04-06', '下周优先级：1) onboarding preview 完整落地 2) CI 稳定 3) TestFlight 反馈回收。', NULL, 'keep', 'demo-2026-04-06-15');
SQL

cat > "$VAULT_DIR/2026-04-04.story.json" <<'EOF'
{
  "dayKey" : "2026-04-04",
  "generatedAt" : 797036400,
  "sections" : [
    {
      "id" : "daily-journal",
      "paragraphs" : [
        { "id" : "daily-journal-0", "sourceEventIDs" : ["A4000000-0000-4000-8000-000000000001"], "text" : "早上打开 Mac 之后，先看到 Slack 里关于 standup 的提醒，今天的主轴很明确，就是把 onboarding preview 和 diary reader 的顺序彻底定下来。" },
        { "id" : "daily-journal-1", "sourceEventIDs" : ["A4000000-0000-4000-8000-000000000002"], "text" : "standup 之后我先在 Notes 里把一句话记死了: 用户第一次看到的应该是整理后的 diary，而不是一排设置项。这句话后来几乎成了我当天所有调整的判断标准。" },
        { "id" : "daily-journal-2", "sourceEventIDs" : ["A4000000-0000-4000-8000-000000000003"], "text" : "接着我在 Safari 里翻 SwiftUI 的 focus 和键盘导航资料，重点看 list 和 detail 之间怎么切换，想把日期列表进故事正文的动作做得更顺手一些。" },
        { "id" : "daily-journal-3", "sourceEventIDs" : ["A4000000-0000-4000-8000-000000000004"], "text" : "有了大概方向以后，我切到 Figma，把 reader 的结构重新摆了一遍。左边日期列收窄，中间正文像一页真实笔记，右边 detail 列则尽量保持稳定，不跟着内容晃。" },
        { "id" : "daily-journal-4", "sourceEventIDs" : ["A4000000-0000-4000-8000-000000000005"], "text" : "回到 Xcode，我先动的是 diary header，把日期层级往上提，让页面一进来先有“这是某一天”的感觉，再把刷新按钮收进右上角，不让它像工具栏里临时插进来的动作。" },
        { "id" : "daily-journal-5", "sourceEventIDs" : ["A4000000-0000-4000-8000-000000000006"], "text" : "中午前我先跑了一轮 `MainWindowViewModelTests`，因为这些阅读器上的调整如果把焦点和选中态搞乱，用户一切日期就会立刻感觉出来。" },
        { "id" : "daily-journal-6", "sourceEventIDs" : ["A4000000-0000-4000-8000-000000000007"], "text" : "午后收到 Mail 里的反馈，说 detail column 的宽度不要跟着内容跳。我读到这句时很认同，因为阅读状态一旦被布局晃动打断，哪怕功能没错，也会显得不可信。" },
        { "id" : "daily-journal-7", "sourceEventIDs" : ["A4000000-0000-4000-8000-000000000008"], "text" : "于是我又去 Safari 看了些长文排版和 Markdown 可读性的资料，想把 story 区真正做成“可连续读”的界面，而不是一段段技术输出堆在一起。" },
        { "id" : "daily-journal-8", "sourceEventIDs" : ["A4000000-0000-4000-8000-000000000009"], "text" : "下午继续改动时，我顺手把 paragraph 记忆也一起收进来，让同一天重新进入故事区时，能回到上次读到的位置。这种细节不大，但会明显减少重新定位的疲劳。" },
        { "id" : "daily-journal-9", "sourceEventIDs" : ["A4000000-0000-4000-8000-000000000010"], "text" : "把交互和文案都理顺后，我在 Terminal 里跑了一轮完整 build，确认这些看起来偏视觉的修改没有带出编译层面的新问题。" },
        { "id" : "daily-journal-10", "sourceEventIDs" : ["A4000000-0000-4000-8000-000000000011"], "text" : "傍晚我在 Ghostty 里收了一次提交，把这天做的内容概括成 header 和 spacing 的打磨。它不是新功能上线那种大动作，但已经让 reader 更接近我脑子里那个“安静、可信、能读下去”的样子。" },
        { "id" : "daily-journal-11", "sourceEventIDs" : ["A4000000-0000-4000-8000-000000000012"], "text" : "晚上收尾时，我又在 Notes 里记下第二天要继续验证的点，尤其是历史日期刷新和 onboarding preview 的故事感。电脑合上之前，这一天的节奏已经从界面草图慢慢落成了比较完整的阅读体验。 " }
      ],
      "title" : ""
    }
  ]
}
EOF

cat > "$VAULT_DIR/2026-04-04.md" <<'EOF'
# 2026-04-04

## 今日小记

早上打开 Mac 之后，先看到 Slack 里关于 standup 的提醒，今天的主轴很明确，就是把 onboarding preview 和 diary reader 的顺序彻底定下来。

standup 之后我先在 Notes 里把一句话记死了: 用户第一次看到的应该是整理后的 diary，而不是一排设置项。这句话后来几乎成了我当天所有调整的判断标准。

接着我在 Safari 里翻 SwiftUI 的 focus 和键盘导航资料，重点看 list 和 detail 之间怎么切换，想把日期列表进故事正文的动作做得更顺手一些。

有了大概方向以后，我切到 Figma，把 reader 的结构重新摆了一遍。左边日期列收窄，中间正文像一页真实笔记，右边 detail 列则尽量保持稳定，不跟着内容晃。

回到 Xcode，我先动的是 diary header，把日期层级往上提，让页面一进来先有“这是某一天”的感觉，再把刷新按钮收进右上角，不让它像工具栏里临时插进来的动作。

中午前我先跑了一轮 `MainWindowViewModelTests`，因为这些阅读器上的调整如果把焦点和选中态搞乱，用户一切日期就会立刻感觉出来。

午后收到 Mail 里的反馈，说 detail column 的宽度不要跟着内容跳。我读到这句时很认同，因为阅读状态一旦被布局晃动打断，哪怕功能没错，也会显得不可信。

于是我又去 Safari 看了些长文排版和 Markdown 可读性的资料，想把 story 区真正做成“可连续读”的界面，而不是一段段技术输出堆在一起。

下午继续改动时，我顺手把 paragraph 记忆也一起收进来，让同一天重新进入故事区时，能回到上次读到的位置。这种细节不大，但会明显减少重新定位的疲劳。

把交互和文案都理顺后，我在 Terminal 里跑了一轮完整 build，确认这些看起来偏视觉的修改没有带出编译层面的新问题。

傍晚我在 Ghostty 里收了一次提交，把这天做的内容概括成 header 和 spacing 的打磨。它不是新功能上线那种大动作，但已经让 reader 更接近我脑子里那个“安静、可信、能读下去”的样子。

晚上收尾时，我又在 Notes 里记下第二天要继续验证的点，尤其是历史日期刷新和 onboarding preview 的故事感。电脑合上之前，这一天的节奏已经从界面草图慢慢落成了比较完整的阅读体验。

---

## 线索来源

- [08:52] Slack (notification): 9 点 standup，今天把 onboarding preview 和 diary reader 的顺序定下来。
- [09:06] Notes (clipboard): 先让用户看到 diary，再解释权限；第一印象应该是结果，不是设置项。
- [09:28] Safari (clipboard): SwiftUI FocusState list detail keyboard navigation macOS
- [09:57] Figma (clipboard): reader 草图：左侧日期窄一些，中间像笔记页，右侧 detail 保持稳定宽度。
- [10:31] Xcode (clipboard): 把 diary header 的日期层级提上来，刷新按钮收进右上角。
- [11:12] Terminal (clipboard): xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
- [12:48] Mail (notification): 反馈：detail column 宽度不要跟内容一起跳，读的时候会分心。
- [13:26] Safari (clipboard): Markdown typography readable long-form notes macOS app
- [14:11] Xcode (clipboard): 记住每一天上次选中的 paragraph，重新进入时恢复那个位置。
- [15:03] Terminal (clipboard): xcodebuild build -scheme KnowYou -destination 'platform=macOS'
- [17:42] Ghostty (clipboard): git commit -m 'feat: polish diary reader spacing and header'
- [20:16] Notes (clipboard): 明天继续：验证历史日期刷新、再检查 onboarding preview 的故事感。
EOF

cat > "$VAULT_DIR/2026-04-05.story.json" <<'EOF'
{
  "dayKey" : "2026-04-05",
  "generatedAt" : 797122800,
  "sections" : [
    {
      "id" : "daily-journal",
      "paragraphs" : [
        { "id" : "daily-journal-0", "sourceEventIDs" : ["A5000000-0000-4000-8000-000000000001"], "text" : "The day started with a Slack standup reminder as soon as I sat down at my Mac. The theme was unusually focused: testing, concurrency, and Beta invites, so the whole day immediately leaned toward engineering cleanup." },
        { "id" : "daily-journal-1", "sourceEventIDs" : ["A5000000-0000-4000-8000-000000000002"], "text" : "My first stretch of work stayed in Safari, rereading Swift Concurrency notes around `Task`, `async/await`, and actor isolation. I wanted the threading model behind the recent code paths to feel crisp again instead of half-remembered." },
        { "id" : "daily-journal-2", "sourceEventIDs" : ["A5000000-0000-4000-8000-000000000003"], "text" : "While reading, I paused in Notes to write down a clearer architectural rule: `AppState` and automation should not carry the same responsibility, and onboarding should never interfere with the real capture pipeline." },
        { "id" : "daily-journal-3", "sourceEventIDs" : ["A5000000-0000-4000-8000-000000000004"], "text" : "From there I moved back into Xcode and focused on the historical-date path in `refreshSelectedDay`. It is the sort of behavior that stays invisible when it works, but feels instantly wrong when an older journal accidentally drags in today's data." },
        { "id" : "daily-journal-4", "sourceEventIDs" : ["A5000000-0000-4000-8000-000000000005"], "text" : "Rather than reasoning about that flow in the abstract, I opened Terminal and ran the focused `MainWindowViewModelTests` slice first. Locking down the path with a real test made the later edits feel much less slippery." },
        { "id" : "daily-journal-5", "sourceEventIDs" : ["A5000000-0000-4000-8000-000000000006"], "text" : "Late in the morning I drifted back to Safari and read through a few GRDB and SQLite persistence patterns. I was mostly checking that the current data model still had room to grow without turning awkward." },
        { "id" : "daily-journal-6", "sourceEventIDs" : ["A5000000-0000-4000-8000-000000000007"], "text" : "In the afternoon I returned to Xcode and trimmed the refresh status copy again. I wanted it to feel less like a utility banner and more like a quiet piece of reader feedback inside the notebook itself." },
        { "id" : "daily-journal-7", "sourceEventIDs" : ["A5000000-0000-4000-8000-000000000008"], "text" : "A Mail notification about the new TestFlight build pulled me out of internal cleanup mode and back into release mode. It was a useful reminder that the product only becomes real once other people actually click through the desktop flow." },
        { "id" : "daily-journal-8", "sourceEventIDs" : ["A5000000-0000-4000-8000-000000000009"], "text" : "That led straight into another Notes pass, where I wrote a short Beta checklist built around the actual Mac workflow: read the story, switch dates, inspect the detail panel, and manually refresh today. Those are the actions the product really lives on." },
        { "id" : "daily-journal-9", "sourceEventIDs" : ["A5000000-0000-4000-8000-000000000010"], "text" : "By early evening I spent a little time in Terminal updating GRDB-related dependencies. It felt less like feature work and more like cleaning the desk before the next round of data-layer changes." },
        { "id" : "daily-journal-10", "sourceEventIDs" : ["A5000000-0000-4000-8000-000000000011"], "text" : "At night I went back to Xcode one more time and pushed the summarizer setup copy further toward optional enhancement rather than mandatory setup. For this app, it still feels important that the story arrives before the extra power does." },
        { "id" : "daily-journal-11", "sourceEventIDs" : ["A5000000-0000-4000-8000-000000000012"], "text" : "Before shutting the laptop, I wrote a quick Notes recap. What felt most settled by the end of the day was the boundary between core reading experience, automation, and add-on capability. A lot of small desktop decisions finally lined up into a cleaner product shape." }
      ],
      "title" : ""
    }
  ]
}
EOF

cat > "$VAULT_DIR/2026-04-05.md" <<'EOF'
# 2026-04-05

## Story

The day started with a Slack standup reminder as soon as I sat down at my Mac. The theme was unusually focused: testing, concurrency, and Beta invites, so the whole day immediately leaned toward engineering cleanup.

My first stretch of work stayed in Safari, rereading Swift Concurrency notes around `Task`, `async/await`, and actor isolation. I wanted the threading model behind the recent code paths to feel crisp again instead of half-remembered.

While reading, I paused in Notes to write down a clearer architectural rule: `AppState` and automation should not carry the same responsibility, and onboarding should never interfere with the real capture pipeline.

From there I moved back into Xcode and focused on the historical-date path in `refreshSelectedDay`. It is the sort of behavior that stays invisible when it works, but feels instantly wrong when an older journal accidentally drags in today's data.

Rather than reasoning about that flow in the abstract, I opened Terminal and ran the focused `MainWindowViewModelTests` slice first. Locking down the path with a real test made the later edits feel much less slippery.

Late in the morning I drifted back to Safari and read through a few GRDB and SQLite persistence patterns. I was mostly checking that the current data model still had room to grow without turning awkward.

In the afternoon I returned to Xcode and trimmed the refresh status copy again. I wanted it to feel less like a utility banner and more like a quiet piece of reader feedback inside the notebook itself.

A Mail notification about the new TestFlight build pulled me out of internal cleanup mode and back into release mode. It was a useful reminder that the product only becomes real once other people actually click through the desktop flow.

That led straight into another Notes pass, where I wrote a short Beta checklist built around the actual Mac workflow: read the story, switch dates, inspect the detail panel, and manually refresh today. Those are the actions the product really lives on.

By early evening I spent a little time in Terminal updating GRDB-related dependencies. It felt less like feature work and more like cleaning the desk before the next round of data-layer changes.

At night I went back to Xcode one more time and pushed the summarizer setup copy further toward optional enhancement rather than mandatory setup. For this app, it still feels important that the story arrives before the extra power does.

Before shutting the laptop, I wrote a quick Notes recap. What felt most settled by the end of the day was the boundary between core reading experience, automation, and add-on capability. A lot of small desktop decisions finally lined up into a cleaner product shape.

---

## Source Notes

- [08:58] Slack (notification): Standup today: testing, concurrency, and Beta invites. Version notes need to be ready before tonight.
- [09:19] Safari (clipboard): Swift Concurrency: Task async/await actor isolation on MainActor
- [09:46] Notes (clipboard): Split AppState from automation responsibilities so onboarding does not interfere with the real capture pipeline.
- [10:21] Xcode (clipboard): Add a historical-date test for refreshSelectedDay so it never triggers notification import by mistake.
- [11:07] Terminal (clipboard): xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
- [12:15] Safari (clipboard): GRDB migration and SQLite app state persistence patterns
- [13:44] Xcode (clipboard): Tighten the refresh status copy so it feels lighter and less like a utility banner.
- [15:09] Mail (notification): A new TestFlight build is available. Invite the Beta group for this round of experience testing.
- [16:02] Notes (clipboard): Beta checklist: read the story, switch dates, inspect detail, manually refresh today.
- [17:18] Terminal (clipboard): brew upgrade grdb && pod repo update
- [19:06] Xcode (clipboard): Make summarizer setup feel optional and additive instead of blocking the onboarding flow.
- [21:12] Notes (clipboard): Today mostly clarified the boundary between testing, copy, and automation. Tomorrow is for CI and investor materials.
EOF

cat > "$VAULT_DIR/2026-04-06.story.json" <<'EOF'
{
  "dayKey" : "2026-04-06",
  "generatedAt" : 797209200,
  "sections" : [
    {
      "id" : "daily-journal",
      "paragraphs" : [
        { "id" : "daily-journal-0", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000001"], "text" : "早上刚坐到电脑前，Calendar 就把今天的节奏先排出来了: 上午设计同步，下午投资人视频通话。这种日程一出来，我就知道今天会在产品细节和对外表达之间来回切。" },
        { "id" : "daily-journal-1", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000002"], "text" : "第一段工作我放在 Figma 里，继续调 reader 的主色和背景关系。把蓝色从 `#2563EB` 收到 `#1D4ED8`，再让正文底色稍微暖一点之后，整个界面终于没那么像默认组件拼起来的样子了。" },
        { "id" : "daily-journal-2", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000003"], "text" : "还没把配色完全看顺，Slack 就弹出 CI 超时的提醒。我对这种消息已经很敏感，因为它会立刻把原本稳定的设计节奏切成一种必须先止血的工程状态。" },
        { "id" : "daily-journal-3", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000004"], "text" : "于是我先去 Safari 查 `xcodebuild` 超时和诊断思路，想确认是测试本身慢，还是最近阅读器这批改动把执行路径拖长了。" },
        { "id" : "daily-journal-4", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000005"], "text" : "查完以后回到 Xcode，我又重新盯了一遍 `@MainActor final class AppState: ObservableObject` 这条主线。很多看似散的状态问题，最后都还是会回到这个中心点上。" },
        { "id" : "daily-journal-5", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000006"], "text" : "中午前我在 Terminal 里直接跑了针对 `MainWindowViewModelTests` 的测试切片，先把最核心的交互路径验证掉。和盲目重跑全套相比，这样更像在电脑里顺着线索一步步逼近问题。" },
        { "id" : "daily-journal-6", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000007"], "text" : "临近中午，我切到 Notes 准备投资人通话的 talking points，把 local-first、story-first、evidence-linked reader 和 privacy boundary 几个点压成最少的几行字，尽量让表达也像产品本身一样干净。" },
        { "id" : "daily-journal-7", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000008"], "text" : "13 点之前，Calendar 的提醒又把我拉进会议状态。整件事都发生在电脑上: 日程弹窗、会议入口、笔记窗口，还有会后要立刻补的材料，全都连在同一块屏幕里。" },
        { "id" : "daily-journal-8", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000009"], "text" : "会后我没有马上回代码，而是先在 Safari 看了一些桌面端日记产品和 onboarding benchmark，想确认自己现在推进的故事预览路线是不是足够有说服力。" },
        { "id" : "daily-journal-9", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000010"], "text" : "下午 Mail 里很快跟来一封 follow-up，请我补一页 MVP 核心指标和近期验证计划。收到这种邮件时，产品讨论就会立刻从界面和体验跳到节奏、数字和下一步证明。" },
        { "id" : "daily-journal-10", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000011"], "text" : "我随即回到 Notes，把 `DAU > 100`、次日留存和真实测试者数量这些指标重新写了一遍。它们看起来像汇报材料，但其实也在反过来约束电脑端的每个体验细节该怎么取舍。" },
        { "id" : "daily-journal-11", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000012"], "text" : "整理完对外材料以后，我又回到 Xcode，把 automation status 和 refresh status 的文案尽量统一。界面里这些小地方如果语气不一致，整个产品就会显得像几个半成品拼在一起。" },
        { "id" : "daily-journal-12", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000013"], "text" : "傍晚我在 Terminal 里跑了完整 build，想给今天这串设计、测试、表达三条线都做个收口。电脑里最踏实的时刻，往往还是看见构建顺利跑完的那一刻。" },
        { "id" : "daily-journal-13", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000014"], "text" : "晚上 Slack 又回了一条设计反馈，说当前配色更稳，detail 宽度固定以后阅读节奏明显好了。读到这里时，我才觉得白天在 Figma 和 reader 之间来回切的那部分力气没有白花。" },
        { "id" : "daily-journal-14", "sourceEventIDs" : ["A6000000-0000-4000-8000-000000000015"], "text" : "收尾时我在 Notes 写下下周优先级，把 onboarding preview、CI 稳定和 TestFlight 反馈放在最前面。一天结束以后回头看，几乎所有内容都还是围绕电脑端这个真实使用场景展开: 看、写、测、开会、收反馈，再把它们重新组织成产品。 " }
      ],
      "title" : ""
    }
  ]
}
EOF

cat > "$VAULT_DIR/2026-04-06.md" <<'EOF'
# 2026-04-06

## 今日小记

早上刚坐到电脑前，Calendar 就把今天的节奏先排出来了: 上午设计同步，下午投资人视频通话。这种日程一出来，我就知道今天会在产品细节和对外表达之间来回切。

第一段工作我放在 Figma 里，继续调 reader 的主色和背景关系。把蓝色从 `#2563EB` 收到 `#1D4ED8`，再让正文底色稍微暖一点之后，整个界面终于没那么像默认组件拼起来的样子了。

还没把配色完全看顺，Slack 就弹出 CI 超时的提醒。我对这种消息已经很敏感，因为它会立刻把原本稳定的设计节奏切成一种必须先止血的工程状态。

于是我先去 Safari 查 `xcodebuild` 超时和诊断思路，想确认是测试本身慢，还是最近阅读器这批改动把执行路径拖长了。

查完以后回到 Xcode，我又重新盯了一遍 `@MainActor final class AppState: ObservableObject` 这条主线。很多看似散的状态问题，最后都还是会回到这个中心点上。

中午前我在 Terminal 里直接跑了针对 `MainWindowViewModelTests` 的测试切片，先把最核心的交互路径验证掉。和盲目重跑全套相比，这样更像在电脑里顺着线索一步步逼近问题。

临近中午，我切到 Notes 准备投资人通话的 talking points，把 local-first、story-first、evidence-linked reader 和 privacy boundary 几个点压成最少的几行字，尽量让表达也像产品本身一样干净。

13 点之前，Calendar 的提醒又把我拉进会议状态。整件事都发生在电脑上: 日程弹窗、会议入口、笔记窗口，还有会后要立刻补的材料，全都连在同一块屏幕里。

会后我没有马上回代码，而是先在 Safari 看了一些桌面端日记产品和 onboarding benchmark，想确认自己现在推进的故事预览路线是不是足够有说服力。

下午 Mail 里很快跟来一封 follow-up，请我补一页 MVP 核心指标和近期验证计划。收到这种邮件时，产品讨论就会立刻从界面和体验跳到节奏、数字和下一步证明。

我随即回到 Notes，把 `DAU > 100`、次日留存和真实测试者数量这些指标重新写了一遍。它们看起来像汇报材料，但其实也在反过来约束电脑端的每个体验细节该怎么取舍。

整理完对外材料以后，我又回到 Xcode，把 automation status 和 refresh status 的文案尽量统一。界面里这些小地方如果语气不一致，整个产品就会显得像几个半成品拼在一起。

傍晚我在 Terminal 里跑了完整 build，想给今天这串设计、测试、表达三条线都做个收口。电脑里最踏实的时刻，往往还是看见构建顺利跑完的那一刻。

晚上 Slack 又回了一条设计反馈，说当前配色更稳，detail 宽度固定以后阅读节奏明显好了。读到这里时，我才觉得白天在 Figma 和 reader 之间来回切的那部分力气没有白花。

收尾时我在 Notes 写下下周优先级，把 onboarding preview、CI 稳定和 TestFlight 反馈放在最前面。一天结束以后回头看，几乎所有内容都还是围绕电脑端这个真实使用场景展开: 看、写、测、开会、收反馈，再把它们重新组织成产品。

---

## 线索来源

- [08:41] Calendar (notification): 10 点设计同步，13 点投资人视频通话。
- [09:03] Figma (clipboard): 主色从 #2563EB 收到 #1D4ED8，正文背景再暖一点，层级更稳。
- [09:37] Slack (notification): CI/CD 流水线失败：测试超时，需要排查。
- [10:02] Safari (clipboard): xcodebuild test timeout diagnostics macOS CI
- [10:46] Xcode (clipboard): @MainActor final class AppState: ObservableObject
- [11:18] Terminal (clipboard): xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
- [12:06] Notes (clipboard): Investor call talking points: local-first, story-first, evidence-linked reader, privacy boundary.
- [13:00] Calendar (notification): 与投资人视频通话 下午 1 点。
- [14:22] Safari (clipboard): daily journal product onboarding benchmark desktop app
- [15:11] Mail (notification): 跟进：请补一页 MVP 核心指标和近期验证计划。
- [15:38] Notes (clipboard): MVP 核心指标：DAU > 100，次日留存 > 40%，首周至少 10 位真实测试者。
- [16:27] Xcode (clipboard): 把 automation status 和 refresh status 文案统一，减少面板感。
- [17:16] Terminal (clipboard): xcodebuild build -scheme KnowYou -destination 'platform=macOS'
- [18:34] Slack (notification): 设计反馈已看：当前配色更稳，detail 宽度固定后阅读节奏明显好一些。
- [20:08] Notes (clipboard): 下周优先级：1) onboarding preview 完整落地 2) CI 稳定 3) TestFlight 反馈回收。
EOF

printf 'Seeded demo data into %s\n' "$ROOT_DIR"
printf '  - %s\n' "$VAULT_DIR/2026-04-04.md"
printf '  - %s\n' "$VAULT_DIR/2026-04-04.story.json"
printf '  - %s\n' "$VAULT_DIR/2026-04-05.md"
printf '  - %s\n' "$VAULT_DIR/2026-04-05.story.json"
printf '  - %s\n' "$VAULT_DIR/2026-04-06.md"
printf '  - %s\n' "$VAULT_DIR/2026-04-06.story.json"
sqlite3 "$DB_PATH" "select dayKey, count(*) from events where dayKey in ('2026-04-04','2026-04-05','2026-04-06') group by dayKey order by dayKey;"
