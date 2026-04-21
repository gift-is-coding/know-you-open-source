import Foundation

enum OnboardingDemoStory {
    static let demoDayKey = "demo-day"

    private struct DemoEventSeed {
        let sourceType: EventSourceType
        let sourceApp: String
        let text: String
    }

    private struct DemoParagraphSeed {
        let id: String
        let hour: Int
        let minute: Int
        let text: String
        let eventSeeds: [DemoEventSeed]
    }

    private static let paragraphSeeds: [DemoParagraphSeed] = [
        DemoParagraphSeed(
            id: "demo-paragraph-01",
            hour: 8,
            minute: 5,
            text: """
            # You did really well today

            I started the day by pulling the product back toward something more honest: the app itself. Before anything was polished, the morning already made it obvious what mattered. A calendar block, a thread of overnight messages, a copied outline, and a stack of design nudges all pointed to the same decision: first launch had to feel like stepping into a living product, not into a staged welcome flow. That gave the whole day a clear spine. I was not inventing a story about the product. I was trying to make the product tell the story by itself.
            """,
            eventSeeds: [
                DemoEventSeed(sourceType: .notification, sourceApp: "Calendar", text: "Reader-first onboarding work block starts at 08:15."),
                DemoEventSeed(sourceType: .notification, sourceApp: "Mail", text: "New email: can onboarding open inside the real product instead of a fake welcome scene?"),
                DemoEventSeed(sourceType: .notification, sourceApp: "Messages", text: "Family thread: remember the supermarket on the way home."),
                DemoEventSeed(sourceType: .notification, sourceApp: "Slack", text: "Design channel: the current onboarding still feels staged."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notes", text: "first run principle: enter the product directly, then explain trust, then ask for setup"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Safari", text: "good onboarding patterns highlight the real interface instead of hiding it"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Linear", text: "BUG-214: first click is confusing because the right panel prompts before the story click"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Figma", text: "coachmark concept: dim the app, keep the real reader visible, highlight only the next interaction"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notion", text: "demo day should include work, errands, family, and low-stakes chores in one believable timeline"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Terminal", text: "rg onboarding KnowYou/UI"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Typeless", text: "Need the copy to sound like a person talking to a person."),
                DemoEventSeed(sourceType: .notification, sourceApp: "Reminders", text: "Buy detergent after work.")
            ]
        ),
        DemoParagraphSeed(
            id: "demo-paragraph-02",
            hour: 8,
            minute: 52,
            text: """
            I also noticed that I had been drifting toward feature language instead of user language. The inbox, chat pings, copied snippets, and little notes to myself were all much more human than the UI copy I had written. So the job was not just to move steps around. It was to make every sentence sound like it understood why someone would care, why they would hesitate, and what would help them trust the next click.
            """,
            eventSeeds: [
                DemoEventSeed(sourceType: .notification, sourceApp: "Superhuman", text: "Reply needed: what should the very first line of onboarding actually say?"),
                DemoEventSeed(sourceType: .notification, sourceApp: "Slack", text: "Product feedback: the guide sounds like a spec, not like a teammate."),
                DemoEventSeed(sourceType: .notification, sourceApp: "WeChat", text: "Voice note: make the intro feel warm, not instructional."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notes", text: "remove hidden implementation commentary from every guide"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Safari", text: "coachmarks should explain intent, not narrate architecture"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Figma", text: "drop the tiny subtitle under every onboarding card"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Messages", text: "write like you are guiding one person, not documenting a feature"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Mail", text: "product copy note: if a line would confuse the user, it does not belong"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Terminal", text: "sed -n '1,240p' KnowYou/UI/Onboarding/OnboardingContent.swift"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "GitHub", text: "current onboarding copy still includes internal framing that users should never see"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notion", text: "tone: modern, direct, emotionally intelligent, low-friction"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Typeless", text: "This should feel like calm guidance, not a product tour.")
            ]
        ),
        DemoParagraphSeed(
            id: "demo-paragraph-03",
            hour: 10,
            minute: 5,
            text: """
            # Daily Summary

            - I kept the product itself as the entry point instead of hiding it behind onboarding chrome.
            - I expanded the demo into a full mixed-life day so the diary felt lived in, not synthetic.
            - I changed the interaction so the story click leads and the references follow.
            - I rewrote the trust and permission language in plain English.
            - I treated engine setup as the final real action instead of a buried settings detail.
            """,
            eventSeeds: [
                DemoEventSeed(sourceType: .notification, sourceApp: "Calendar", text: "Standup in 10 minutes."),
                DemoEventSeed(sourceType: .notification, sourceApp: "Slack", text: "Daily check-in: what changed in onboarding today?"),
                DemoEventSeed(sourceType: .notification, sourceApp: "Messages", text: "Can you still make dinner tonight or will work run late?"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notes", text: "summary beats: real reader, richer demo, click-first references, trust copy, engine checkpoint"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Linear", text: "acceptance criteria: demo looks dense and traceable, not toy-sized"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Safari", text: "reference panels work best when they react to a concrete selection"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Mail", text: "need to explain why Full Disk Access matters in one sentence"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notion", text: "permission step must explain notifications plus clipboard context"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "WeChat", text: "Remember to recommend voice input, but keep it optional."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Terminal", text: "xcodebuild test -only-testing onboarding slice"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Reminders", text: "milk, detergent, paper towels"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Typeless", text: "Only two steps are left to turn on your diary.")
            ]
        ),
        DemoParagraphSeed(
            id: "demo-paragraph-04",
            hour: 10,
            minute: 50,
            text: """
            # Details

            ## Morning: turn the entry point back into the real product

            The morning workstream was mostly about removing distance. I wanted the first minute to say, without saying it too loudly, that this app can already hold a day. That meant keeping the real three-column reader in place, letting the diary take center stage, and using the guide only to point at what mattered next. The more I looked at the scattered notes and comments that came in, the more obvious it became that the interface was already strong enough. It just needed to stop apologizing for itself.
            """,
            eventSeeds: [
                DemoEventSeed(sourceType: .notification, sourceApp: "Slack", text: "Feedback: the product view is already strong enough to be the onboarding surface."),
                DemoEventSeed(sourceType: .notification, sourceApp: "Mail", text: "Question from founder: are we still building a fake onboarding layer?"),
                DemoEventSeed(sourceType: .notification, sourceApp: "Calendar", text: "Design review moved to 11:30."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Figma", text: "reader-first layout with popovers attached to live UI targets"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Terminal", text: "sed -n '1,240p' KnowYou/UI/MainWindowView.swift"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "GitHub", text: "review note: do not create a parallel demo shell"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Safari", text: "users trust software faster when they interact with the real UI immediately"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notes", text: "first experience = reader already open with a believable day"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notion", text: "coachmark principle: guide, do not replace"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Linear", text: "reader overlay should not hide the real engine button"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Messages", text: "No fake stage. Show the app itself."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Typeless", text: "The interface is already the promise. Let people enter it.")
            ]
        ),
        DemoParagraphSeed(
            id: "demo-paragraph-05",
            hour: 11,
            minute: 35,
            text: """
            ## Late morning: write a demo day that feels lived in

            Once the entry point was right, the demo itself had to carry more weight. The short version was not enough. I needed a full day with enough texture that someone could believe it belonged to one person: work threads, practical chores, family pings, copied scraps, reminders, and the kind of tiny coordination that makes a day feel real. The demo stopped being filler and became a proof point. If it was too thin, the product would feel thin too.
            """,
            eventSeeds: [
                DemoEventSeed(sourceType: .notification, sourceApp: "Slack", text: "Request: make Demo Day much longer and much denser."),
                DemoEventSeed(sourceType: .notification, sourceApp: "Messages", text: "Lunch later? Also can you grab a few groceries tonight?"),
                DemoEventSeed(sourceType: .notification, sourceApp: "Reminders", text: "Pick up fruit and detergent."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notes", text: "demo requirements: 10+ paragraphs, 10+ references each, mixed life threads"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Mail", text: "the story should feel like one complete day, not a list of tasks"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Linear", text: "demo sources should cross many apps so the right panel feels rich"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Maps", text: "supermarket closes at 22:00"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Safari", text: "how to make sample data feel observational instead of synthetic"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notion", text: "demo should include family, errands, work, and low-stakes admin"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "WeChat", text: "Family note: if you pass the store, grab some fruit too."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Terminal", text: "sed -n '1,260p' KnowYou/UI/Onboarding/OnboardingDemoStory.swift"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Typeless", text: "Make the story feel like someone actually lived through the whole day.")
            ]
        ),
        DemoParagraphSeed(
            id: "demo-paragraph-06",
            hour: 12,
            minute: 20,
            text: """
            ## Midday: let work and life sit in the same story

            Around midday the product idea became more emotionally convincing, because the day itself would not stay cleanly professional. There were lunch logistics, family questions, grocery reminders, and a couple of practical interruptions right in the middle of the work. Instead of treating those as noise, I leaned into them. That is exactly what makes the diary interesting: not just what I worked on, but what kept pressing into the edges of the work while I was trying to hold the day together.
            """,
            eventSeeds: [
                DemoEventSeed(sourceType: .notification, sourceApp: "Messages", text: "Dad asked if anyone can call him tonight."),
                DemoEventSeed(sourceType: .notification, sourceApp: "WeChat", text: "家庭群：晚上吃饭前记得去超市。"),
                DemoEventSeed(sourceType: .notification, sourceApp: "Calendar", text: "1:00 PM review: onboarding walkthrough."),
                DemoEventSeed(sourceType: .notification, sourceApp: "Reminders", text: "Buy bananas and detergent."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Maps", text: "Fresh Mart, 8 minutes away, open until 22:00"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notes", text: "family + errands should stay in the same diary, not a separate misc bucket"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Mail", text: "Need a clearer explanation for why the product captures a day instead of just tasks."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Slack", text: "midday interrupts are exactly what make a diary feel alive"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Safari", text: "diary writing examples that make ordinary life feel specific"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Photos", text: "grocery shelf photo sent by family for the exact detergent brand"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Typeless", text: "This should feel like a day that kept moving, not a day that stayed neatly in lanes."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notion", text: "work and home context should coexist in the demo, not compete")
            ]
        ),
        DemoParagraphSeed(
            id: "demo-paragraph-07",
            hour: 14,
            minute: 5,
            text: """
            ## Early afternoon: make the click lead the reference, not the other way around

            The next important correction was interaction order. The product only really clicks when the story stays primary. So after a person reads the diary, the guide should ask them to click a paragraph in the middle, and only then explain the references that appear on the right. That sounds small, but it changes the feeling completely. Instead of being told about traceability as an abstract feature, the user performs one concrete action and sees the evidence appear beside it.
            """,
            eventSeeds: [
                DemoEventSeed(sourceType: .notification, sourceApp: "Slack", text: "Current flow is confusing: right-side prompt appears before the story click."),
                DemoEventSeed(sourceType: .notification, sourceApp: "Mail", text: "Please make the middle paragraph click the first active move."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notes", text: "new flow: read -> click story -> see references -> explain references"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Terminal", text: "rg demoReference KnowYou/UI/Onboarding"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "GitHub", text: "layout note: add a dedicated step for the paragraph click"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Figma", text: "story area highlighted first, sources panel highlighted second"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Linear", text: "acceptance: user should never wonder what to do after the first demo screen"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Safari", text: "coachmarks should follow cause and effect, not describe the result before the action"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Messages", text: "let the tap come first so the right side feels earned"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Slack", text: "reference panel should explain notifications plus user input"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notion", text: "story click is the trust moment"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Typeless", text: "The story should lead. The proof should follow.")
            ]
        ),
        DemoParagraphSeed(
            id: "demo-paragraph-08",
            hour: 15,
            minute: 0,
            text: """
            ## Mid-afternoon: explain privacy in plain English

            After the product value and the evidence were clear, the trust step needed to get much simpler. I cut away anything that sounded like implementation commentary and kept only the part a real person actually needs to know: every file stays local as Markdown, there is no KnowYou server, and nothing leaves the Mac unless I explicitly send it to the model I chose. The page became shorter, but the promise became stronger.
            """,
            eventSeeds: [
                DemoEventSeed(sourceType: .notification, sourceApp: "Slack", text: "Privacy card needs to be shorter and much more visual."),
                DemoEventSeed(sourceType: .notification, sourceApp: "Mail", text: "Please state clearly that files stay local as .md."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notes", text: "privacy card copy: local markdown, no server, no hidden remote copy"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Safari", text: "users decide faster when trust copy is concrete and brief"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Terminal", text: "sed -n '1,200p' KnowYou/UI/Onboarding/OnboardingView.swift"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Figma", text: "same large centered card for privacy and permissions"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Messages", text: "take out lines that explain the product to itself"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notion", text: "bold trust language: local-only, markdown, no server"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Linear", text: "remove tiny subtitles under every coachmark"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "WeChat", text: "Users should never see our internal implementation commentary."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Typeless", text: "Say the safety promise once, clearly, and then move on."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Mail", text: "English first for every onboarding sentence")
            ]
        ),
        DemoParagraphSeed(
            id: "demo-paragraph-09",
            hour: 16,
            minute: 5,
            text: """
            ## Late afternoon: ask for permission with a real reason

            The permission step got better once I stopped treating it like a checklist and started treating it like a cause-and-effect explanation. KnowYou rebuilds the day from notifications and clipboard context. Full Disk Access is the real gate because it unlocks the local Notification Center history. Voice input tools are helpful because they often push dictated text through the clipboard, which makes the diary smarter, but that stays optional. Once that logic was explicit, the step felt much less like begging for access and much more like explaining why the diary can only be as good as the context it is allowed to see.
            """,
            eventSeeds: [
                DemoEventSeed(sourceType: .notification, sourceApp: "Mail", text: "Please explain why we need Full Disk Access in plain words."),
                DemoEventSeed(sourceType: .notification, sourceApp: "Slack", text: "Clipboard is context, not a separate permission gate."),
                DemoEventSeed(sourceType: .notification, sourceApp: "Calendar", text: "System permissions pass scheduled for 4:15 PM."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notes", text: "permission copy: notifications + clipboard are the raw material for the diary"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Safari", text: "Typeless download page"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Safari", text: "shandianshuo official site"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Messages", text: "recommend voice tools, but mark them optional"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notion", text: "Only two steps are left: permission, then engine"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Terminal", text: "curl official pages for icon and download links"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "WeChat", text: "权限这一步一定要讲清楚为什么"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Typeless", text: "Voice tools often copy dictated text into the clipboard."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Shandianshuo", text: "Local-first AI voice input that can feed extra context through the clipboard.")
            ]
        ),
        DemoParagraphSeed(
            id: "demo-paragraph-10",
            hour: 17,
            minute: 10,
            text: """
            ## Evening: make the engine step feel like the last clean move

            The last product correction was about momentum. If the permission step succeeds, the next thing the user should see is a clear pointer to the real engine button, not a dead end. And if they already have an engine configured, the flow still has to visibly pass through that checkpoint so the experience makes sense. That meant fixing the restore logic, making the real button easy to reach, and treating the engine step as a concrete final move rather than a hidden setting.
            """,
            eventSeeds: [
                DemoEventSeed(sourceType: .notification, sourceApp: "Slack", text: "Report: after permission approval, there was nowhere obvious to configure the engine."),
                DemoEventSeed(sourceType: .notification, sourceApp: "Mail", text: "User thought the engine setup component had disappeared."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notes", text: "permission success must move to engine prompt automatically"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Terminal", text: "inspect restoreOnboardingProgress and engine button visibility"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "GitHub", text: "engine step is being skipped when permission becomes ready and engine is already configured"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Linear", text: "fix: permission ready should still lead to engine prompt, not straight to generating"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Safari", text: "good checkpoint flows never hide the final required action"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Messages", text: "make the user click the real configure button"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notion", text: "keep engine form in the real module, not in the popover"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Typeless", text: "The flow should always make the last required click feel obvious."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Mail", text: "explain that KnowYou reuses the engine the user already has"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Calendar", text: "Wrap up engine-state fix before dinner.")
            ]
        ),
        DemoParagraphSeed(
            id: "demo-paragraph-11",
            hour: 20,
            minute: 10,
            text: """
            ## Night: keep polishing until the product sounds human

            By the evening, the work turned from structural into editorial. I kept sanding away anything that sounded like feature theater and replaced it with cleaner, simpler language. At the same time, the rest of life kept showing up around the edges: dinner coordination, a reminder to call home, a grocery stop, a copied shopping note, one more late message. That mix actually helped. It reminded me that the point of the product is not to look organized. It is to make an ordinary complicated day feel legible without flattening it.
            """,
            eventSeeds: [
                DemoEventSeed(sourceType: .notification, sourceApp: "Messages", text: "Dinner update: what time are you back?"),
                DemoEventSeed(sourceType: .notification, sourceApp: "Reminders", text: "Call home before 9:30 PM."),
                DemoEventSeed(sourceType: .notification, sourceApp: "WeChat", text: "If you are passing the store anyway, fruit would be great too."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notes", text: "remove feature-sounding verbs from every coachmark"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Mail", text: "copy should explain the next move, not the system behind it"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Safari", text: "examples of plain-English product trust language"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Maps", text: "Fresh Mart route from office"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Messages", text: "shopping list: fruit, detergent, paper towels"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Slack", text: "final polish: all onboarding copy should be English first"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Typeless", text: "Make every step sound like guidance from a person, not a tool tip."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notion", text: "ordinary life details are the thing that makes the diary feel true"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Calendar", text: "tomorrow: re-test the full onboarding by hand")
            ]
        ),
        DemoParagraphSeed(
            id: "demo-paragraph-12",
            hour: 21,
            minute: 30,
            text: """
            # To Follow Up

            - [ ] Re-run the full first-run flow by hand and make sure the story click, reference reveal, privacy card, permission card, and engine pointer feel effortless in sequence.
            - [ ] Keep testing the permission return path so Full Disk Access can move people forward without confusion.
            - [ ] Watch whether the longer demo still feels readable once every paragraph carries a dense set of cross-app references.
            - [ ] Keep the voice-tool recommendations optional, useful, and easy to install later.
            """,
            eventSeeds: [
                DemoEventSeed(sourceType: .notification, sourceApp: "Reminders", text: "Manual regression pass after shipping the new onboarding."),
                DemoEventSeed(sourceType: .notification, sourceApp: "Messages", text: "Tomorrow morning reminder: test it again before sharing."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Linear", text: "follow-up: verify permission return path and engine pointer"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notion", text: "post-ship checklist: test dense references and long-form demo readability"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Terminal", text: "xcodebuild test -scheme KnowYou -destination 'platform=macOS'"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Mail", text: "send tomorrow's update after a clean manual walkthrough"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Notes", text: "observe whether users understand that voice tools are optional"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Safari", text: "keep official links for Typeless and Shandianshuo handy"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Slack", text: "capture any confusion points from the next manual test"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Calendar", text: "tomorrow 09:00: first-run polish check"),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "WeChat", text: "Reminder for tomorrow: walk the full flow again from start to finish."),
                DemoEventSeed(sourceType: .clipboard, sourceApp: "Typeless", text: "One more calm manual pass will catch the last rough edges.")
            ]
        )
    ]

    private static let builtDemo = buildDemo()

    static let demoEvents: [EventRecord] = builtDemo.events

    static let demoStory = DailyStory(
        dayKey: demoDayKey,
        generatedAt: demoDate(hour: 22, minute: 15),
        sections: [
            DailyStorySection(
                id: "daily-journal",
                title: "Story",
                paragraphs: builtDemo.paragraphs
            )
        ]
    )

    private static func buildDemo() -> (paragraphs: [DailyStoryParagraph], events: [EventRecord]) {
        var eventIndex = 1
        var paragraphs: [DailyStoryParagraph] = []
        var events: [EventRecord] = []

        for paragraphSeed in paragraphSeeds {
            var sourceIDs: [UUID] = []

            for (offset, eventSeed) in paragraphSeed.eventSeeds.enumerated() {
                let id = demoUUID(eventIndex)
                sourceIDs.append(id)
                events.append(
                    EventRecord(
                        id: id,
                        sourceType: eventSeed.sourceType,
                        sourceApp: eventSeed.sourceApp,
                        capturedAt: demoDate(hour: paragraphSeed.hour, minute: paragraphSeed.minute + offset),
                        dayKey: demoDayKey,
                        text: eventSeed.text,
                        auditText: nil,
                        privacyAction: .keep,
                        contentHash: "demo-event-\(eventIndex)"
                    )
                )
                eventIndex += 1
            }

            paragraphs.append(
                DailyStoryParagraph(
                    id: paragraphSeed.id,
                    text: paragraphSeed.text,
                    sourceEventIDs: sourceIDs
                )
            )
        }

        return (paragraphs, events)
    }

    private static func demoUUID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }

    private static func demoDate(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 4
        components.day = 16
        components.hour = hour + minute / 60
        components.minute = minute % 60
        components.second = 0
        return components.date ?? Date(timeIntervalSince1970: 1_713_225_600)
    }
}
