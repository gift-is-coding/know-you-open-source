import AppKit
import SwiftUI

struct VoiceInputRunningApplication: Equatable {
    let localizedName: String?
    let bundleIdentifier: String?
    let bundlePath: String?

    init(localizedName: String?, bundleIdentifier: String?, bundlePath: String?) {
        self.localizedName = localizedName
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
    }

    init(application: NSRunningApplication) {
        self.init(
            localizedName: application.localizedName,
            bundleIdentifier: application.bundleIdentifier,
            bundlePath: application.bundleURL?.path
        )
    }

    var searchableText: String {
        [
            localizedName,
            bundleIdentifier,
            bundlePath
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }
}

struct VoiceInputRecommendation: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let logoAssetName: String
    let downloadURL: URL

    init(id: String, name: String, detail: String, logoAssetName: String, downloadURL: String) {
        self.id = id
        self.name = name
        self.detail = detail
        self.logoAssetName = logoAssetName
        self.downloadURL = URL(string: downloadURL)!
    }
}

struct VoiceInputNudgePresentation: Equatable {
    let title: String
    let detail: String
    let principle: String
    let attentionSystemImage: String
    let laterButtonTitle: String
    let dismissButtonTitle: String
    let recommendations: [VoiceInputRecommendation]

    static let recommendations: [VoiceInputRecommendation] = [
        VoiceInputRecommendation(
            id: "typeless",
            name: "Typeless",
            detail: "AI dictation for long-form English and multilingual input across apps.",
            logoAssetName: "VoiceInputLogoTypeless",
            downloadURL: "https://www.typeless.com/downloads"
        ),
        VoiceInputRecommendation(
            id: "shandianshuo",
            name: "闪电说",
            detail: "A Chinese AI voice input app for fast spoken capture and polished text.",
            logoAssetName: "VoiceInputLogoShandianshuo",
            downloadURL: "https://shandianshuo.cn/"
        )
    ]

    static func make(
        runningApplications: [VoiceInputRunningApplication],
        isPermanentlyDismissed: Bool,
        snoozedUntil: Date?,
        now: Date
    ) -> VoiceInputNudgePresentation? {
        guard isPermanentlyDismissed == false else { return nil }
        if let snoozedUntil, snoozedUntil > now {
            return nil
        }
        guard VoiceInputAppDetector.containsKnownVoiceInputApp(runningApplications) == false else {
            return nil
        }

        return VoiceInputNudgePresentation(
            title: "Use voice input",
            detail: "Speak naturally, then let KnowYou turn the captured text into diary context.",
            principle: "Voice input -> clipboard -> KnowYou reads the clipboard and drafts your diary.",
            attentionSystemImage: "exclamationmark.circle.fill",
            laterButtonTitle: "Later",
            dismissButtonTitle: "Don't show again",
            recommendations: recommendations
        )
    }
}

enum VoiceInputAppDetector {
    private static let knownAliases = [
        "apple dictation",
        "voice control",
        "dictationim",
        "com.apple.speech",
        "superwhisper",
        "super whisper",
        "wispr flow",
        "wispr",
        "ai.wispr",
        "aqua voice",
        "aquavoice",
        "withaqua",
        "macwhisper",
        "whisper transcription",
        "voice memos",
        "quicktime player",
        "otter",
        "notta",
        "typeless",
        "com.typeless",
        "闪电说",
        "shandianshuo",
        "lightning says",
        "代体",
        "daiti",
        "讯飞输入法",
        "iflytek",
        "com.iflytek",
        "搜狗输入法",
        "sogou",
        "com.sogou",
        "百度输入法",
        "baidu input",
        "com.baidu.input",
        "微信输入法",
        "wetype",
        "com.tencent.wetype"
    ]

    static func detectRunningApplications() -> [VoiceInputRunningApplication] {
        NSWorkspace.shared.runningApplications.map(VoiceInputRunningApplication.init(application:))
    }

    static func containsKnownVoiceInputApp(_ runningApplications: [VoiceInputRunningApplication]) -> Bool {
        runningApplications.contains { app in
            let searchableText = app.searchableText
            return knownAliases.contains { searchableText.contains($0) }
        }
    }
}

struct VoiceInputNudgeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.orange)
                .frame(width: 32, height: 32)
                .background(Color.orange.opacity(0.14), in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.orange.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: Color.orange.opacity(0.18), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set up voice input")
        .help("Set up voice input")
    }
}

struct VoiceInputNudgePopover: View {
    let presentation: VoiceInputNudgePresentation
    let onOpen: (URL) -> Void
    let onLater: () -> Void
    let onNever: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: presentation.attentionSystemImage)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.orange)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(.headline)
                    Text(presentation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(presentation.principle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(presentation.recommendations) { recommendation in
            VoiceInputRecommendationRow(
                            recommendation: recommendation,
                            onOpen: onOpen
                        )
                    }
                }
            }
            .frame(maxHeight: 300)

            HStack {
                Button(presentation.laterButtonTitle, action: onLater)
                Spacer()
                Button(presentation.dismissButtonTitle, action: onNever)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

private struct VoiceInputRecommendationRow: View {
    let recommendation: VoiceInputRecommendation
    let onOpen: (URL) -> Void

    var body: some View {
        HStack(spacing: 10) {
            VoiceInputLogo(assetName: recommendation.logoAssetName)

            VStack(alignment: .leading, spacing: 3) {
                Text(recommendation.name)
                    .font(.subheadline.weight(.semibold))
                Text(recommendation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Download") {
                onOpen(recommendation.downloadURL)
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct VoiceInputLogo: View {
    let assetName: String

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
            .padding(4)
            .frame(width: 36, height: 36)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}
