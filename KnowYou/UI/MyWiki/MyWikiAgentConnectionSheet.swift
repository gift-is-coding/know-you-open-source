import AppKit
import SwiftUI

struct MyWikiAgentConnectionSheet: View {
    let presentation: MyWikiAgentConnectionPresentation
    @Binding var selectedClient: MyWikiAgentClient
    @Binding var setupRefreshID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var copyStatus: String?
    @State private var setupStatusMessage: String?
    @State private var isShowingAdvancedConfig = false

    private let agentInstaller = MyWikiAgentConfigurationInstaller()
    private let instructionLauncher = MyWikiAgentInstructionLauncher()

    private var currentConfiguration: String? {
        presentation.configuration(for: selectedClient)
    }

    private var selectedSetupStatus: MyWikiAgentSetupStatus {
        guard let currentConfiguration else { return .notSetUp }
        _ = setupRefreshID
        return agentInstaller.setupStatus(for: selectedClient, expectedConfiguration: currentConfiguration)
    }

    private var canRunInstructionInSelectedClient: Bool {
        instructionLauncher.canRunInstruction(in: selectedClient)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Use My Wiki with Agents")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Add My Wiki to an agent so it can ask KnowYou for private, cited context when needed.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            if presentation.isReady == false {
                readinessSection
            }

            wizardSection
            advancedConfigSection

            HStack {
                if let copyStatus {
                    Text(copyStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(24)
        .frame(width: 900, height: 680, alignment: .topLeading)
        .background(MyWikiTheme.contentBackground)
    }

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                presentation.statusTitle,
                systemImage: presentation.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(presentation.isReady ? .green : .yellow)
            .font(.headline)

            Text(presentation.statusDetail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(MyWikiTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var wizardSection: some View {
        HStack(alignment: .top, spacing: 14) {
            stepCard(
                number: 1,
                title: "Choose an agent"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pick where you want My Wiki to help.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    ForEach(MyWikiAgentClient.allCases) { client in
                        agentChoice(client)
                    }
                }
            } footer: {
                Text("Built-in agents can be set up automatically. Use manual setup for anything else.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            stepCard(
                number: 2,
                title: presentation.setupTitle(for: selectedClient)
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(presentation.setupDescription(for: selectedClient))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    installStatusRow("My Wiki project", isReady: presentation.projectRootPath != "Not configured")
                    installStatusRow("KnowYou app", isReady: presentation.isReady)
                    installStatusRow("\(selectedClient.title) setup", isReady: selectedClient.supportsAutomaticInstall && selectedSetupStatus == .ready)

                    if let setupStatusMessage {
                        Text(setupStatusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } footer: {
                if selectedClient.supportsAutomaticInstall {
                    Button {
                        enableSelectedAgent()
                    } label: {
                        Text(selectedSetupStatus == .ready ? "Update \(selectedClient.title)" : "Add My Wiki")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentConfiguration == nil)
                } else {
                    Button {
                        copyConfiguration()
                    } label: {
                        Label("Copy Setup", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(currentConfiguration == nil)
                }
            }

            stepCard(
                number: 3,
                title: canRunInstructionInSelectedClient ? "Run this instruction" : "Copy this instruction"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(canRunInstructionInSelectedClient ? presentation.instructionRunSetupCopy(for: selectedClient) : presentation.instructionSetupCopy(for: selectedClient))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ScrollView {
                        Text(presentation.agentInstruction)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10)
                    }
                    .frame(height: 150)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            } footer: {
                VStack(spacing: 8) {
                    if canRunInstructionInSelectedClient {
                        Button {
                            runInstruction()
                        } label: {
                            Label(presentation.instructionRunButtonTitle(for: selectedClient), systemImage: "terminal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedSetupStatus != .ready)
                    }

                    Button {
                        copyInstruction()
                    } label: {
                        Label("Copy Instruction", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            stepCard(
                number: 4,
                title: "Test and use"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedSetupStatus == .ready ? "\(selectedClient.title) is ready. Restart it once, then ask normally." : "After setup, restart the agent once so it can load My Wiki.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Try asking")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("What have I been working on recently around agents and My Wiki?")
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(MyWikiTheme.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if selectedSetupStatus == .ready {
                        Label("My Wiki context is available", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                }
            } footer: {
                Button("Done") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var advancedConfigSection: some View {
        DisclosureGroup("Advanced MCP Config", isExpanded: $isShowingAdvancedConfig) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Client", selection: $selectedClient) {
                    ForEach(MyWikiAgentClient.allCases) { client in
                        Text(client.title).tag(client)
                    }
                }
                .pickerStyle(.segmented)

                ScrollView {
                    Text(currentConfiguration ?? "Complete the missing setup above before copying an agent config.")
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                .frame(minHeight: 130)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    copyConfiguration()
                } label: {
                    Label("Copy MCP Config", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(currentConfiguration == nil)
            }
            .padding(.top, 8)
        }
    }

    private func stepCard<Content: View, Footer: View>(
        number: Int,
        title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(myWikiRGBColor: MyWikiAgentStepBadgePalette.standard.foreground))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color(myWikiRGBColor: MyWikiAgentStepBadgePalette.standard.background))
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                Spacer()
            }
            .padding(14)
            .frame(height: 64, alignment: .leading)
            .background(MyWikiTheme.cardBackground)

            content()
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            footer()
                .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 430)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MyWikiTheme.border, lineWidth: 1))
    }

    private func agentChoice(_ client: MyWikiAgentClient) -> some View {
        Button {
            selectedClient = client
        } label: {
            HStack(spacing: 10) {
                Image(systemName: client == .codex ? "terminal" : "sparkle.magnifyingglass")
                    .frame(width: 28, height: 28)
                    .background(MyWikiTheme.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(client.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(client.supportsAutomaticInstall ? "Automatic setup" : "Copy setup manually")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(selectedClient == client ? MyWikiTheme.selectionBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedClient == client ? Color.accentColor.opacity(0.35) : MyWikiTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func installStatusRow(_ title: String, isReady: Bool) -> some View {
        Label(title, systemImage: isReady ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isReady ? .green : .secondary)
    }

    private func copyConfiguration() {
        guard let currentConfiguration else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentConfiguration, forType: .string)
        copyStatus = "\(selectedClient.title) MCP config copied."
    }

    private func copyInstruction() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(presentation.agentInstruction, forType: .string)
        copyStatus = "Instruction copied."
    }

    private func runInstruction() {
        do {
            try instructionLauncher.runInstruction(in: selectedClient, instruction: presentation.agentInstruction)
            copyStatus = "\(selectedClient.title) opened with My Wiki instructions."
        } catch {
            copyStatus = "Could not open \(selectedClient.title): \(error.localizedDescription)"
        }
    }

    private func enableSelectedAgent() {
        guard let currentConfiguration else { return }

        do {
            let result = try agentInstaller.enable(selectedClient, configuration: currentConfiguration)
            setupRefreshID = UUID()
            let skillMessage = result.didInstallSkill ? "My Wiki Skill installed." : "No separate Skill was needed."
            if result.backupURL != nil {
                setupStatusMessage = "My Wiki was added to \(result.client.title). \(skillMessage) A backup was created. Restart \(result.client.title) once."
            } else {
                setupStatusMessage = "My Wiki was added to \(result.client.title). \(skillMessage) Restart \(result.client.title) once."
            }
        } catch {
            setupStatusMessage = "Could not add My Wiki to \(selectedClient.title): \(error.localizedDescription)"
        }
    }
}

private extension Color {
    init(myWikiRGBColor color: MyWikiRGBColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}
