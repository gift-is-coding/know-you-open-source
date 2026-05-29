import SwiftUI
import AppKit

enum OnboardingCoachmarkTargetID: Hashable {
    case storyPanel
    case sourcesPanel
    case engineButton
}

struct OnboardingCoachmarkTargetPreferenceKey: PreferenceKey {
    static let defaultValue: [OnboardingCoachmarkTargetID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [OnboardingCoachmarkTargetID: Anchor<CGRect>], nextValue: () -> [OnboardingCoachmarkTargetID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func onboardingCoachmarkTarget(_ target: OnboardingCoachmarkTargetID) -> some View {
        anchorPreference(key: OnboardingCoachmarkTargetPreferenceKey.self, value: .bounds) {
            [target: $0]
        }
    }
}

struct OnboardingRenderPlan: Equatable {
    let usesRealReaderChrome: Bool
    let keepsSourcesPanelVisible: Bool
    let showsEngineButton: Bool
    let highlightedTarget: OnboardingCoachmarkTarget
    let coachmarkTitle: String
    let coachmarkBody: String
    let activationStepLabel: String?
    let activationFollowupLabel: String?

    init(step: OnboardingStep, content: OnboardingStepContent) {
        usesRealReaderChrome = true
        keepsSourcesPanelVisible = true
        showsEngineButton = true
        highlightedTarget = content.target
        coachmarkTitle = content.title
        coachmarkBody = content.body
        activationStepLabel = content.activationStepLabel
        activationFollowupLabel = content.activationFollowupLabel
    }
}

private struct OnboardingCoachmarkCardStyle {
    let titlePointSize: CGFloat
    let iconPointSize: CGFloat
    let iconContainerSize: CGFloat
    let iconCornerRadius: CGFloat
    let bodyFont: Font
    let padding: CGFloat
    let cornerRadius: CGFloat
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    static let compact = OnboardingCoachmarkCardStyle(
        titlePointSize: 20,
        iconPointSize: 15,
        iconContainerSize: 28,
        iconCornerRadius: 8,
        bodyFont: .subheadline,
        padding: 18,
        cornerRadius: 18,
        shadowOpacity: 0.12,
        shadowRadius: 18,
        shadowY: 10
    )

    static let prominent = OnboardingCoachmarkCardStyle(
        titlePointSize: 28,
        iconPointSize: 18,
        iconContainerSize: 32,
        iconCornerRadius: 10,
        bodyFont: .callout,
        padding: 24,
        cornerRadius: 28,
        shadowOpacity: 0.18,
        shadowRadius: 28,
        shadowY: 18
    )
}

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    let onComplete: () -> Void

    @State private var step: OnboardingStep
    @State private var summarizerConfig = SummarizerConfig.load()
    @State private var isEngineSheetPresented = false
    @State private var isHistoryBootstrapConfirmationPresented = false
    @State private var generationStarted = false
    @State private var generationMessage = "Preparing your first 7 days..."
    @State private var generationError: String?
    @State private var referenceAdvancePolicy = OnboardingReferenceAdvancePolicy()
    @State private var referenceAdvanceTask: Task<Void, Never>?
    @State private var didBypassFullDiskAccessForDevelopment = false

    init(
        onComplete: @escaping () -> Void,
        initialStep: OnboardingStep = .demoRead
    ) {
        self.onComplete = onComplete
        _step = State(initialValue: initialStep)
        _didBypassFullDiskAccessForDevelopment = State(
            initialValue: OnboardingPermissionBypassPolicy.hasStoredDevelopmentBypass(bundleURL: Bundle.main.bundleURL)
        )
    }

    var body: some View {
        MainWindowView(
            showsOnboardingEngineButton: renderPlan.showsEngineButton,
            onOpenEngineSetup: openEngineSetup,
            onStoryParagraphTap: handleStoryParagraphTap
        )
        .environment(appState)
        .overlayPreferenceValue(OnboardingCoachmarkTargetPreferenceKey.self) { preferences in
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(overlayOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)

                    if let highlightRect = highlightedRect(from: preferences, in: proxy) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.9), lineWidth: 2)
                            .frame(width: highlightRect.width + 12, height: highlightRect.height + 12)
                            .position(x: highlightRect.midX, y: highlightRect.midY)
                            .shadow(color: Color.accentColor.opacity(0.18), radius: 12, x: 0, y: 0)
                            .allowsHitTesting(false)
                    }

                    coachmarkLayer(preferences: preferences, proxy: proxy)
                }
            }
        }
        .sheet(isPresented: $isEngineSheetPresented) {
            engineSetupSheet
        }
        .alert(
            OnboardingHistoryBootstrapConfirmation.title,
            isPresented: $isHistoryBootstrapConfirmationPresented
        ) {
            Button(OnboardingHistoryBootstrapConfirmation.confirmButtonTitle) {
                finishOnboardingAfterHistoryConfirmation()
            }
        } message: {
            Text(.init(OnboardingHistoryBootstrapConfirmation.message))
        }
        .onAppear {
            summarizerConfig = SummarizerConfig.load()
            if appState.environment != nil {
                appState.refreshServiceStatuses()
                reconcileVisibleStepWithProgress()
            }
            appState.presentOnboardingDemoIfNeeded()
            prepareStorySelectionForCurrentStep()
            syncEngineSheetPresentation()
        }
        .onChange(of: step) { _, newStep in
            appState.resumeOnboardingStep(newStep)
            prepareStorySelectionForCurrentStep()
            syncEngineSheetPresentation()
            if newStep != .demoClick {
                referenceAdvanceTask?.cancel()
                referenceAdvanceTask = nil
                referenceAdvancePolicy.reset()
            }
        }
        .onChange(of: notificationsAvailable) { _, _ in
            guard appState.environment != nil else { return }
            reconcileVisibleStepWithProgress()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard appState.environment != nil else { return }
            appState.refreshServiceStatuses()
            reconcileVisibleStepWithProgress()
        }
        .task(id: step.rawValue) {
            if step == .generating {
                await startAutomaticGenerationIfNeeded()
            }
        }
    }

    private var currentContent: OnboardingStepContent {
        OnboardingContent.content(for: step)
    }

    private var renderPlan: OnboardingRenderPlan {
        OnboardingRenderPlan(step: step, content: currentContent)
    }

    private var notificationsAvailable: Bool {
        appState.notificationStatus.isDatabaseAvailable || appState.environment?.notificationReader.isAvailable == true
    }

    private var allowsFullDiskAccessBypass: Bool {
        OnboardingPermissionBypassPolicy.allowsFullDiskAccessBypass(bundleURL: Bundle.main.bundleURL)
    }

    private var permissionsReadyForOnboarding: Bool {
        notificationsAvailable || didBypassFullDiskAccessForDevelopment
    }

    private var reminderAuthorizationStatus: ReminderAuthorizationStatus {
        appState.endOfDayReminderConfig.authorizationStatus
    }

    private var reminderNotificationsReady: Bool {
        reminderAuthorizationStatus == .authorized
    }

    private var reminderNotificationDetail: String {
        switch reminderAuthorizationStatus {
        case .authorized:
            return "Ready. Know You can send your 8:30 PM daily review reminder."
        case .denied:
            return "Optional. Notifications are currently off in macOS. Used for the 8:30 PM daily review reminder."
        case .notDetermined:
            return "Optional. Used for the 8:30 PM daily review reminder."
        }
    }

    private var isEngineConfigured: Bool {
        summarizerConfig.makeSummarizer() != nil
    }

    private var overlayOpacity: Double {
        switch step {
        case .demoRead, .demoClick, .demoReference, .enginePrompt:
            return 0.16
        case .privacy, .permissions, .generating:
            return 0.28
        case .engineSetup:
            return 0.08
        }
    }

    @ViewBuilder
    private func coachmarkLayer(
        preferences: [OnboardingCoachmarkTargetID: Anchor<CGRect>],
        proxy: GeometryProxy
    ) -> some View {
        switch currentContent.target {
        case .storyPanel:
            if let rect = preferences[.storyPanel].map({ proxy[$0] }) {
                anchoredCard(rect: rect, width: 320, proxy: proxy) {
                    coachmarkCard(style: .compact)
                }
            }
        case .sourcesPanel:
            if let rect = preferences[.sourcesPanel].map({ proxy[$0] }) {
                anchoredCard(rect: rect, width: 300, proxy: proxy, yOffset: 52) {
                    coachmarkCard(style: .compact)
                }
            }
        case .engineButton:
            if let rect = preferences[.engineButton].map({ proxy[$0] }) {
                engineAnchoredCard(rect: rect, width: 300, proxy: proxy) {
                    coachmarkCard(style: .compact)
                }
            }
        case .sharedCenterCard:
            centeredCard {
                coachmarkCard(style: .prominent)
            }
        case .engineSheet:
            EmptyView()
        }
    }

    private func coachmarkCard(style: OnboardingCoachmarkCardStyle) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let activationStepLabel = currentContent.activationStepLabel {
                HStack(spacing: 10) {
                    Text(activationStepLabel)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.14), in: Capsule(style: .continuous))

                    if let activationFollowupLabel = currentContent.activationFollowupLabel {
                        Text(activationFollowupLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: currentContent.iconName)
                        .font(.system(size: style.iconPointSize, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: style.iconContainerSize, height: style.iconContainerSize)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: style.iconCornerRadius, style: .continuous))

                    Text(currentContent.title)
                        .font(.system(size: style.titlePointSize, weight: .semibold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(currentContent.body)
                    .font(style.bodyFont)
                    .foregroundStyle(.secondary)
            }

            if step == .permissions {
                VStack(alignment: .leading, spacing: 10) {
                    statusRow(
                        title: "Full Disk Access",
                        detail: notificationsAvailable
                            ? "Ready. KnowYou can read the local Notification Center store and rebuild who reached you and when."
                            : "Turn this on in macOS so KnowYou can read the local Notification Center store and rebuild who reached you and when.",
                        ok: notificationsAvailable
                    )

                    statusRow(
                        title: "Notifications",
                        detail: reminderNotificationDetail,
                        ok: reminderNotificationsReady
                    )

                    HStack(spacing: 12) {
                        if reminderAuthorizationStatus == .authorized {
                            Label("Notifications On", systemImage: "checkmark.circle.fill")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.green)
                        } else {
                            Button(reminderAuthorizationStatus == .denied ? "Open Notification Settings" : "Enable Notifications") {
                                if reminderAuthorizationStatus == .denied {
                                    openNotificationSettings()
                                } else {
                                    Task { @MainActor in
                                        await appState.requestDailyReviewReminderAuthorization()
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if let optionalEnhancement = currentContent.optionalEnhancement {
                        Text(optionalEnhancement.title)
                            .font(.headline)

                        Text(optionalEnhancement.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 10) {
                            ForEach(optionalEnhancement.helperLinks) { helperLink in
                                helperLinkCard(helperLink)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if step == .generating {
                HStack(spacing: 12) {
                    if generationError == nil {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    Text(generationError ?? generationMessage)
                        .font(.body.weight(.medium))
                }
            }

            cardActions
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(style.shadowOpacity), radius: style.shadowRadius, x: 0, y: style.shadowY)
    }

    @ViewBuilder
    private var cardActions: some View {
        switch step {
        case .demoRead, .demoReference, .privacy:
            HStack {
                Spacer()
                Button(currentContent.primaryCTA) {
                    advance()
                }
                .buttonStyle(.borderedProminent)
            }

        case .demoClick:
            EmptyView()

        case .permissions:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button("Open Full Disk Access") {
                        openFullDiskAccess()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(currentContent.primaryCTA) {
                        recheckPermissionAndAdvanceIfReady()
                    }
                    .buttonStyle(.bordered)
                }

                if !notificationsAvailable && allowsFullDiskAccessBypass {
                    Button("Continue in this dev build without Full Disk Access") {
                        advancePastPermissionsForDevelopment()
                    }
                    .buttonStyle(.bordered)
                }
            }

        case .enginePrompt:
            EmptyView()

        case .engineSetup:
            EmptyView()

        case .generating:
            EmptyView()
        }
    }

    private var engineSetupSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(currentContent.activationStepLabel ?? "2/2")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.14), in: Capsule(style: .continuous))

            Text(currentContent.title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))

            Text(currentContent.body)
                .font(.callout)
                .foregroundStyle(.secondary)

            EngineConfigurationSection(
                summarizerConfig: $summarizerConfig,
                lead: "Reuse the CLI or API setup you already trust on this Mac. Once this looks good, KnowYou can start working right away.",
                footnote: "Launching at login is recommended if you want the diary to keep updating in the background."
            )

            HStack {
                Button("Back") {
                    step = .enginePrompt
                    isEngineSheetPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(currentContent.primaryCTA) {
                    persistEngineConfiguration()
                    step = .generating
                    isEngineSheetPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isEngineConfigured)
            }
        }
        .padding(28)
        .frame(width: 520)
        .interactiveDismissDisabled(true)
    }

    private func anchoredCard<Content: View>(
        rect: CGRect,
        width: CGFloat,
        proxy: GeometryProxy,
        yOffset: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let maxOriginX = max(24, proxy.size.width - width - 24)
        let originX = max(24, min(rect.minX + 18, maxOriginX))
        let originY = max(24, min(rect.minY + yOffset, proxy.size.height - 220))

        return content()
            .frame(width: width)
            .offset(x: originX, y: originY)
    }

    private func engineAnchoredCard<Content: View>(
        rect: CGRect,
        width: CGFloat,
        proxy: GeometryProxy,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let maxOriginX = max(24, proxy.size.width - width - 24)
        let originX = max(24, min(rect.maxX - width, maxOriginX))
        let topY = max(20, rect.maxY + 14)

        return content()
            .frame(width: width)
            .offset(x: originX, y: topY)
    }

    private func centeredCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: 460)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func highlightedRect(
        from preferences: [OnboardingCoachmarkTargetID: Anchor<CGRect>],
        in proxy: GeometryProxy
    ) -> CGRect? {
        switch currentContent.target {
        case .storyPanel:
            return preferences[.storyPanel].map { proxy[$0] }
        case .sourcesPanel:
            return preferences[.sourcesPanel].map { proxy[$0] }
        case .engineButton:
            return preferences[.engineButton].map { proxy[$0] }
        case .sharedCenterCard, .engineSheet:
            return nil
        }
    }

    private func statusRow(title: String, detail: String, ok: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func helperLinkCard(_ helperLink: OnboardingHelperLink) -> some View {
        Link(destination: helperLink.url) {
            HStack(spacing: 14) {
                AsyncImage(url: helperLink.iconURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Image(systemName: "mic.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 42, height: 42)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(helperLink.title)
                            .font(.headline)

                        Text("Optional")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule(style: .continuous))
                    }

                    Text(helperLink.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func advance() {
        guard let next = step.next else { return }
        step = next
    }

    private func prepareStorySelectionForCurrentStep() {
        guard step == .demoRead || step == .demoClick else { return }
        appState.clearOnboardingDemoStorySelection()
    }

    private func handleStoryParagraphTap(_: String) {
        guard step == .demoClick else { return }
        guard appState.selectedStorySourceEvents.isEmpty == false else { return }

        let now = Date()
        let shouldAdvance = referenceAdvancePolicy.registerValidParagraphSelection(at: now)
        if shouldAdvance {
            advanceToReferenceStep()
            return
        }

        referenceAdvanceTask?.cancel()
        referenceAdvanceTask = Task { @MainActor in
            let nanoseconds = UInt64(referenceAdvancePolicy.delaySeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard step == .demoClick else { return }
            if referenceAdvancePolicy.shouldAdvanceReferenceStep(at: Date()) {
                advanceToReferenceStep()
            }
        }
    }

    private func advanceToReferenceStep() {
        referenceAdvanceTask?.cancel()
        referenceAdvanceTask = nil
        referenceAdvancePolicy.reset()
        if step == .demoClick {
            step = .demoReference
        }
    }

    private func openEngineSetup() {
        guard step == .enginePrompt || step == .engineSetup else { return }
        step = .engineSetup
        isEngineSheetPresented = true
    }

    private func syncEngineSheetPresentation() {
        isEngineSheetPresented = step == .engineSetup
    }

    private func persistEngineConfiguration() {
        appState.applySummarizerConfig(summarizerConfig)
        appState.refreshServiceStatuses()
    }

    private func recheckPermissionAndAdvanceIfReady() {
        appState.recheckNotificationAccess()
        if !notificationsAvailable && allowsFullDiskAccessBypass {
            OnboardingPermissionBypassPolicy.storeDevelopmentBypass(bundleURL: Bundle.main.bundleURL)
            didBypassFullDiskAccessForDevelopment = true
        }
        reconcileVisibleStepWithProgress()
    }

    private func advancePastPermissionsForDevelopment() {
        guard allowsFullDiskAccessBypass else { return }
        OnboardingPermissionBypassPolicy.storeDevelopmentBypass(bundleURL: Bundle.main.bundleURL)
        didBypassFullDiskAccessForDevelopment = true
        appState.restoreOnboardingProgress(
            isFullDiskAccessReady: false,
            isEngineReady: isEngineConfigured,
            allowsFullDiskAccessBypass: true
        )
        if appState.currentOnboardingStep == .enginePrompt {
            step = .enginePrompt
        }
    }

    private func reconcileVisibleStepWithProgress() {
        appState.restoreOnboardingProgress(
            isFullDiskAccessReady: notificationsAvailable,
            isEngineReady: isEngineConfigured,
            allowsFullDiskAccessBypass: didBypassFullDiskAccessForDevelopment
        )

        guard let resolvedStep = appState.currentOnboardingStep else { return }
        if resolvedStep != step {
            step = resolvedStep
        }
    }

    private func startAutomaticGenerationIfNeeded() async {
        guard !generationStarted else { return }

        generationStarted = true
        generationError = nil
        generationMessage = "Preparing your first 7 days..."

        persistEngineConfiguration()

        guard appState.environment != nil else {
            generationMessage = "Preparing the real generation environment..."
            return
        }

        guard permissionsReadyForOnboarding else {
            generationError = "Full Disk Access is still missing. Turn it on so KnowYou can rebuild your notification context."
            generationStarted = false
            return
        }

        guard isEngineConfigured else {
            generationError = "Your engine is not ready yet. Finish 2/2 first."
            generationStarted = false
            return
        }

        generationMessage = "Review the local-only first generation…"
        try? await Task.sleep(nanoseconds: 500_000_000)

        guard step == .generating else { return }
        isHistoryBootstrapConfirmationPresented = true
    }

    private func finishOnboardingAfterHistoryConfirmation() {
        guard step == .generating else { return }
        generationMessage = "Generating your first 7 days…"
        appState.completeOnboarding()
        onComplete()
    }

    private func openFullDiskAccess() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func openNotificationSettings() {
        if let deepLink = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            if NSWorkspace.shared.open(deepLink) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
