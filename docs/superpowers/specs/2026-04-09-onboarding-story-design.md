# Onboarding Story Flow Design

## Summary

This design replaces the current utility-style onboarding with a five-step story about a user's day. The goal is to keep users clicking by showing a coherent narrative, establish trust in local-first storage and automated filtering early, preview the final diary outcome before any permission ask, and then request permissions with clear justification tied to product value.

The flow remains a linear SwiftUI wizard so it fits the current app structure, but every step shifts from setup mechanics to story progression.

## Goals

- Turn onboarding into a story users want to continue through.
- State local-first storage clearly on the first screen.
- Explain automated capture in plain language.
- Establish trust through concrete privacy boundaries, not generic reassurance.
- Show the end result before requesting permissions.
- Ask for permissions only after the user understands what they unlock.
- Keep vault and summarizer setup compatible with the current app architecture.

## Non-Goals

- Redesign the main reader outside of an onboarding preview.
- Add new signal sources beyond clipboard and notifications.
- Implement real cloud sync inside onboarding.
- Build an onboarding editor or a fully dynamic template system.

## User Promise

Know You quietly helps the user remember their day, keeps the source material in local Markdown files, filters sensitive content before it is stored or synced, and only asks for permissions after showing the value of enabling them.

## Narrative Direction

Tone:

- Primary tone: warm, companion-like
- Secondary tone: restrained, trustworthy

Narrative arc:

1. A day begins.
2. Know You notices the user's working context automatically.
3. Know You explains the safety boundary around what it keeps.
4. Know You shows the user what their finished day looks like.
5. Know You asks for permissions as the final enabling step.

This flow should feel like a guided story, not a checklist of system settings.

## Proposed Step Model

The onboarding should move from 3 steps to 5 steps:

1. `intro`
2. `capture`
3. `safety`
4. `preview`
5. `permissions`

The wizard container remains linear with back/next navigation, but button labels should reflect narrative progression rather than generic setup language.

## Step Design

### Step 1: Intro

Purpose:

- Open with emotional clarity rather than configuration.
- Immediately anchor trust with a local-first promise.

Content:

- Hero title about Know You helping the user remember the day from the moment work begins.
- Supporting copy that says the product turns scattered context into a readable diary.
- A small but clearly visible line under the hero:
  - "Your information stays in Markdown files stored on your own Mac."
- A lightweight visual suggesting a day unfolding, not a folder picker.

Requirements:

- This local-storage line must be visible without scrolling or interaction.
- The line must read as a fact, not a footnote hidden in tertiary UI.

Primary button:

- Replace `Continue` with story-forward copy such as "See how your day comes together".

### Step 2: Capture

Purpose:

- Explain what happens automatically during the day.
- Make passive capture feel useful rather than invasive.

Content blocks:

- Messages and notifications:
  - We automatically capture message notifications so the user remembers what reached them during the day.
- Clipboard context:
  - We automatically use clipboard activity to understand what the user was reading, writing, collecting, or comparing.
- Voice input helper:
  - Recommend installing a voice-to-text helper and explain that voice input often lands in the clipboard, which gives Know You better context.
  - Provide outbound links or tappable icon treatments for suggested tools.

Requirements:

- This screen must explicitly say the process is automatic.
- It must mention notification capture and clipboard capture in plain product language.
- The voice-input explanation must describe why clipboard-based voice input improves context.

Copy constraints:

- Do not frame this as surveillance.
- Do frame it as low-friction memory capture.

### Step 3: Safety

Purpose:

- Resolve privacy tension created by the previous step.
- Explain both local storage and filtering boundaries concretely.

Content:

- All captured content is filtered automatically before it becomes durable memory.
- Even local files are filtered, not raw dumps.
- Sensitive items such as bank-card numbers, passwords, OTPs, tokens, and similar secrets should not be saved locally or uploaded.
- Sync is optional:
  - The user can now or later sync their Markdown files to Openclaw or Claude.
  - Doing so improves agent memory and context.
  - This enhancement is optional and built on top of the user's own local files.

Requirements:

- This screen must state that sensitive data protection applies even to local files.
- It must present sync as optional enhancement, never as default behavior.
- It must connect sync to improved memory/context for agents.

Primary button:

- Use copy that leads into the result, such as "Show me what my day could look like".

### Step 4: Preview

Purpose:

- Show the result before asking for permissions.
- Make the value concrete using the app's existing reader language.

Content:

- A polished preview page modeled on the current app:
  - left-side date or time progression
  - central diary/story content from morning to night
  - right-side detail/source flavor, enough to imply traceability
- The diary content should show a coherent day:
  - morning setup or planning
  - midday conversations and copied context
  - afternoon work progression
  - evening wrap-up or reflection

Requirements:

- The preview should feel close to the real product, not like a marketing illustration detached from the app.
- It must imply that the story is grounded in real captured signals.
- It should visually peak here so the permission request that follows feels earned.

### Step 5: Permissions

Purpose:

- Ask for permissions only after trust and value are established.
- Tie each permission to a visible user outcome.

Content:

- Explain that Know You needs relevant local-reading permissions to reconstruct the day reliably.
- Explain the notification-related permission in terms of preserving important moments and conversations.
- Explain that ongoing access allows the process to stay automatic instead of manual.
- Reassure the user that they can defer and return later if needed.

Requirements:

- Do not lead with raw macOS permission jargon.
- Do not present permissions as technical hurdles.
- Each permission ask must have a plain-language "why this matters" explanation next to it.

Potential permission rows:

- Clipboard:
  - automatic context capture
- Notifications / Full Disk Access:
  - message and event recovery from the local notification database
- Any additional local reading framing:
  - needed to assemble the day into a complete journal

## Configuration Placement

The current onboarding includes vault selection and summarizer setup. Those concerns should be retained but repositioned so they do not break the story.

Recommended treatment:

- Vault choice:
  - Keep the current default vault behavior.
  - Move explicit folder choosing out of the first hero moment.
  - Present storage location as a fact in the story, with an optional "change location" affordance either on the permission screen or as a secondary inline action.
- Summarizer setup:
  - Remove it from the main onboarding story flow.
  - Defer summarizer selection to Settings or a post-onboarding enhancement prompt.

Reasoning:

- Vault path setup is important but not emotionally suitable as the opening page.
- Summarizer setup is an advanced configuration step and weakens first-run completion.

## UX and Visual Direction

The visual direction should feel calmer and more intentional than the current bare utility wizard.

Guidance:

- Use a stronger hero layout on the intro screen.
- Replace generic SF Symbol-only pages with richer scene composition.
- Use consistent story progression language in button labels.
- Keep the frame compact enough for the existing macOS window, but allow more expressive layout inside each step.
- Make the preview screen the visual high point.

The design should still feel like Know You, not a separate microsite living inside the app.

## Interaction Rules

- Progress indicators should reflect 5 steps, not 3.
- Back remains available from step 2 onward.
- Next button labels can vary per step.
- The final action should not read as a generic `Finish`; it should indicate enabling the experience, such as "Turn it on" or "Start remembering my days".

## Data and State Implications

The onboarding view likely needs a richer step model than an integer index.

Expected structural changes:

- Replace integer-based step switching with a dedicated onboarding-step enum.
- Add step-specific metadata:
  - title
  - CTA label
  - optional secondary actions
- Keep completion behavior using the existing `hasCompletedOnboarding` flag.
- Preserve vault persistence via `AppState.applyVaultURL`.
- Preserve summarizer configuration persistence if needed, but remove it from first-run critical path.

## Content Requirements Checklist

The final onboarding content must explicitly include these product facts:

- Files are stored locally in Markdown files.
- Users can now or later sync those files to Openclaw or Claude.
- Sync improves agent memory/context.
- Capture is automatic.
- Notifications and clipboard are automatically captured.
- Sensitive information is automatically filtered.
- Sensitive items should not be uploaded to the cloud or retained in local files.
- Voice input tools are recommended and can feed context through the clipboard.
- A result preview appears before permission requests.
- Permission asks explain why local-reading access is needed.

## Testing Strategy

At design level, implementation should cover:

- Step rendering tests for all five onboarding steps.
- Navigation tests for back/next progression and final completion.
- Content assertions for required trust/safety copy.
- Preview-screen snapshot or equivalent UI verification if practical.
- Regression checks that onboarding completion still hands off to the main app correctly.

## Risks

- Overwriting the story with too much explanatory copy could slow progression.
- Hiding storage configuration too deeply could reduce user control.
- If the preview looks too synthetic, the permission screen will feel manipulative rather than persuasive.
- If safety language is vague, the whole narrative loses credibility.

## Recommendation

Implement the onboarding as a five-step linear story wizard inside the existing SwiftUI container. Keep storage as a clearly stated local-first fact from the first screen, move advanced configuration out of the emotional critical path, show a believable day-preview before permissions, and ask for permissions only after the user has seen both the value and the privacy boundary.
