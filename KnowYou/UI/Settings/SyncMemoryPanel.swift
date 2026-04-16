import SwiftUI

struct SyncMemoryPanelChannelRow: Equatable {
    let title: String
    let status: String
    let detail: String
}

struct SyncMemoryPanelPresentation: Equatable {
    let channelRows: [SyncMemoryPanelChannelRow]
    let isAutoSyncDailyEnabled: Bool
    let autoSyncDescription = "When enabled, Know You syncs all daily notes to connected memory targets."
    let statusMessage: String?

    init(obsidianPath: String?, openClawPath: String?, isAutoSyncDailyEnabled: Bool, statusMessage: String? = nil) {
        channelRows = [
            SyncMemoryPanelChannelRow(
                title: "Obsidian",
                status: Self.status(for: obsidianPath),
                detail: Self.detail(for: obsidianPath)
            ),
            SyncMemoryPanelChannelRow(
                title: "OpenClaw",
                status: Self.status(for: openClawPath),
                detail: Self.detail(for: openClawPath)
            ),
        ]
        self.isAutoSyncDailyEnabled = isAutoSyncDailyEnabled
        self.statusMessage = statusMessage
    }

    private static func detail(for path: String?) -> String {
        guard let path, path.isEmpty == false else {
            return "Not connected"
        }
        return path
    }

    private static func status(for path: String?) -> String {
        guard let path, path.isEmpty == false else {
            return "Missing"
        }
        return "Ready"
    }
}

struct SyncMemoryPanel: View {
    let obsidianPath: String?
    let openClawPath: String?
    let statusMessage: String?
    @Binding var isAutoSyncDailyEnabled: Bool
    @Binding var dailySyncTime: Date
    let onChooseObsidian: () -> Void
    let onChooseOpenClaw: () -> Void
    let onOpenObsidian: () -> Void
    let onOpenOpenClaw: () -> Void
    let onSyncNow: () -> Void
    let onClose: () -> Void

    private var presentation: SyncMemoryPanelPresentation {
        SyncMemoryPanelPresentation(
            obsidianPath: obsidianPath,
            openClawPath: openClawPath,
            isAutoSyncDailyEnabled: isAutoSyncDailyEnabled,
            statusMessage: statusMessage
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sync Memory")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Copy your daily note history into Obsidian and OpenClaw.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(presentation.channelRows, id: \.title) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.title)
                                .font(.headline)
                            Spacer()
                            Text(row.status)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(row.status == "Ready" ? .green : .secondary)
                        }
                        Text(row.detail)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack {
                        Button("Change Folder") {
                            if row.title == "Obsidian" {
                                onChooseObsidian()
                            } else {
                                onChooseOpenClaw()
                            }
                        }
                        if row.detail != "Not connected" {
                            Button("Open Folder") {
                                if row.title == "Obsidian" {
                                    onOpenObsidian()
                                } else {
                                    onOpenOpenClaw()
                                }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Auto Sync Daily", isOn: $isAutoSyncDailyEnabled)
                DatePicker(
                    "Daily Sync Time",
                    selection: $dailySyncTime,
                    displayedComponents: .hourAndMinute
                )
                .disabled(!isAutoSyncDailyEnabled)
                Text(presentation.autoSyncDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let statusMessage = presentation.statusMessage, statusMessage.isEmpty == false {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Sync Now", action: onSyncNow)
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 320)
    }
}
