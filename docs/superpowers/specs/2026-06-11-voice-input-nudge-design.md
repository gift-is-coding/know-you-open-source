# Voice Input Nudge Design Spec

## Background

KnowYou's diary generation depends on local input flow: the user speaks into a voice input tool, that tool writes text into the current input field or clipboard, and KnowYou reads clipboard/local events to draft diary context. After onboarding, if no known voice input or dictation app is running, the global toolbar should show a visible but non-error nudge beside Diary Engine.

## Goals

- Detect common running voice input apps after the user reaches the main window.
- If none is detected, show a noticeable amber exclamation entry beside the Diary Engine selector. It must not use red/error styling.
- Clicking the entry opens a small popover recommending voice input and explaining the flow: `Voice input -> clipboard -> KnowYou reads the clipboard and drafts your diary.`
- The popover recommends only Typeless and 闪电说, each with its real product logo, a short use-case description, and an official download link.
- The user can download an app, choose `Later`, or choose `Don't show again`.

## Interaction Rules

### Display Conditions

The nudge appears only when all conditions are true:

- The user has reached the main window and is not blocked in onboarding.
- No known voice input/dictation app is running.
- The user has not chosen `Don't show again`.
- The user is not inside the 7-day `Later` snooze window.

Detection uses case-insensitive matching over `NSWorkspace.shared.runningApplications` localized name, bundle identifier, and bundle URL. It should suppress the nudge for:

- Apple Dictation / Voice Control / DictationIM 等系统听写相关进程
- Typeless
- 闪电说 / Shandianshuo / 代体
- Superwhisper
- Wispr Flow / Flow
- Aqua Voice / Aqua
- MacWhisper / Whisper Transcription
- 讯飞输入法
- 搜狗输入法
- 百度输入法
- 微信输入法 / WeType
- Voice Memos / QuickTime Player / Otter / Notta 等常见语音记录或转写软件

### Toolbar Nudge

- 放在 Diary Engine selector 左侧，视觉上属于同一组 toolbar controls。
- Use `exclamationmark.circle.fill` in an amber circular badge.
- Make it more noticeable than secondary toolbar chrome, but do not use red/error styling.
- Do not show long inline copy, so Diary Engine stays the primary toolbar control.
- Accessibility label: `Set up voice input`.

### Popover Content

Popover 宽度约 380-420，内容分三段：

1. Title: `Use voice input`
2. Small explanation: `Speak naturally, then let KnowYou turn the captured text into diary context.`
3. Principle: `Voice input -> clipboard -> KnowYou reads the clipboard and drafts your diary.`
4. Recommendation list: each item includes a real product logo, name, short explanation, and `Download` button.

The recommendation list keeps only two primary options:

- Typeless：`https://www.typeless.com/downloads`
- 闪电说：`https://shandianshuo.cn/`

Footer buttons:

- `Later`: hide the nudge for 7 days.
- `Don't show again`: permanently dismiss the nudge.

### Non-Goals

- Do not install software automatically.
- Do not enable system dictation permissions automatically.
- Do not read microphone or recording permission state.
- Do not treat missing voice input as a Diary Engine error.
- Do not change clipboard ingestion or diary generation logic.

## Architecture

- Add `VoiceInputNudgePresentation` for recommendations, display conditions, copy, logo asset names, and snooze rules.
- Add `VoiceInputAppDetector` to normalize running apps and match known voice input aliases.
- `AppState` owns profile-aware UserDefaults persistence for the snooze deadline and permanent dismissal.
- `MainWindowView` renders the nudge button beside Diary Engine and presents `VoiceInputNudgePopover`.
- Download buttons open official URLs through `NSWorkspace.shared.open`; KnowYou does not download inside the app.

## Testing

- presentation tests：
  - show the nudge when no voice app is running and it has not been dismissed.
  - hide the nudge when Typeless, 闪电说, or another known voice input tool is running.
  - hide during an active snooze window and show again after the snooze expires.
  - hide after permanent dismissal.
  - include only Typeless and 闪电说 URLs.
  - expose `VoiceInputLogoTypeless` and `VoiceInputLogoShandianshuo` asset names.
- AppState tests：
  - `snoozeVoiceInputNudge()` stores a deadline 7 days in the future.
  - `dismissVoiceInputNudgePermanently()` stores permanent dismissal.
- UI/build verification:
  - the toolbar can show both the voice nudge and Diary Engine selector.
  - the popover compiles, displays logo assets, and its actions are non-blocking.
