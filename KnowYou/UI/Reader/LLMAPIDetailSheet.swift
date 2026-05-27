import SwiftUI

struct LLMAPIDetailSheet: View {
    @Binding var config: SummarizerConfig
    let activeStatus: EngineRuntimeStatus
    let providerStatuses: [LLMAPIProviderID: EngineRuntimeStatus]
    let isTesting: Bool
    let onClose: () -> Void
    let onSave: () -> Void
    let onTestProvider: (LLMAPIProviderID) -> Void
    let onSetActive: (LLMAPIProviderID) -> Void

    @State private var selectedProviderID: LLMAPIProviderID

    init(
        config: Binding<SummarizerConfig>,
        activeStatus: EngineRuntimeStatus,
        providerStatuses: [LLMAPIProviderID: EngineRuntimeStatus],
        isTesting: Bool,
        onClose: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onTestProvider: @escaping (LLMAPIProviderID) -> Void,
        onSetActive: @escaping (LLMAPIProviderID) -> Void
    ) {
        _config = config
        self.activeStatus = activeStatus
        self.providerStatuses = providerStatuses
        self.isTesting = isTesting
        self.onClose = onClose
        self.onSave = onSave
        self.onTestProvider = onTestProvider
        self.onSetActive = onSetActive
        _selectedProviderID = State(initialValue: config.wrappedValue.activeLLMAPIProviderID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 16) {
                providerList
                    .frame(width: 250)
                Divider()
                providerDetail
                    .frame(width: 520)
            }

            footer
        }
        .padding(20)
        .frame(width: 820)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LLM API")
                .font(.title3.weight(.semibold))
            HStack(spacing: 8) {
                EngineIndicatorLight(state: activeStatus.state)
                Text(activeStatus.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(LLMAPIProviderID.allCases) { providerID in
                Button {
                    selectedProviderID = providerID
                } label: {
                    providerRow(providerID)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func providerRow(_ providerID: LLMAPIProviderID) -> some View {
        let descriptor = providerID.descriptor
        let status = status(for: providerID)
        let isSelected = selectedProviderID == providerID
        let isActive = config.activeLLMAPIProviderID == providerID

        return HStack(alignment: .center, spacing: 8) {
            EngineIndicatorLight(state: status.state)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(descriptor.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if isActive {
                        badge("Active")
                    }
                }
                if descriptor.isOpenAICompatible {
                    Text("OpenAI-compatible")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(descriptor.defaultWireFormat.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var providerDetail: some View {
        let descriptor = selectedProviderID.descriptor
        let status = status(for: selectedProviderID)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.displayName)
                        .font(.headline)
                    HStack(spacing: 8) {
                        EngineIndicatorLight(state: status.state)
                        Text(status.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if config.activeLLMAPIProviderID == selectedProviderID {
                    badge("Active")
                }
            }

            TextField("Base URL", text: binding(for: \.baseURL))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            TextField("Model", text: binding(for: \.model))
                .textFieldStyle(.roundedBorder)

            SecureField("API Token", text: binding(for: \.apiToken))
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Wire Format")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selectedProviderConfig.wireFormat.displayName)
                    .font(.body.monospaced())
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(selectedProviderConfig.wireFormat.shortDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Link("Apply for API key", destination: descriptor.keyURL)
                Link("API docs", destination: descriptor.docsURL)
            }
            .font(.caption)

            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
            Button("Close", action: onClose)
            Spacer()
            Button("Set Active") {
                onSetActive(selectedProviderID)
            }
            .disabled(!selectedProviderConfig.isComplete)
            Button(isTesting ? "Testing..." : "Test Provider") {
                onTestProvider(selectedProviderID)
            }
            .disabled(isTesting || !selectedProviderConfig.isComplete)
            Button("Save", action: onSave)
                .buttonStyle(.borderedProminent)
        }
    }

    private var selectedProviderConfig: LLMAPIProviderConfig {
        config.llmAPIProviderConfig(for: selectedProviderID) ?? selectedProviderID.defaultConfig
    }

    private func binding(for keyPath: WritableKeyPath<LLMAPIProviderConfig, String>) -> Binding<String> {
        Binding(
            get: { selectedProviderConfig[keyPath: keyPath] },
            set: { newValue in
                updateSelectedProviderConfig { providerConfig in
                    providerConfig[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func updateSelectedProviderConfig(_ update: (inout LLMAPIProviderConfig) -> Void) {
        var nextConfig = config
        var providerConfig = nextConfig.llmAPIProviderConfig(for: selectedProviderID)
            ?? selectedProviderID.defaultConfig
        update(&providerConfig)
        nextConfig.setLLMAPIProviderConfig(providerConfig)
        config = nextConfig
    }

    private func status(for providerID: LLMAPIProviderID) -> EngineRuntimeStatus {
        if providerID == config.activeLLMAPIProviderID {
            return providerStatuses[providerID] ?? activeStatus
        }
        if let providerStatus = providerStatuses[providerID] {
            return providerStatus
        }
        let providerConfig = config.llmAPIProviderConfig(for: providerID) ?? providerID.defaultConfig
        if providerConfig.isComplete {
            return EngineRuntimeStatus(
                state: .yellow,
                detail: "Provider configured. Test required.",
                lastVerifiedAt: nil,
                configurationSignature: ""
            )
        }
        return EngineRuntimeStatus(
            state: .gray,
            detail: "API configuration is incomplete.",
            lastVerifiedAt: nil,
            configurationSignature: ""
        )
    }

    private func badge(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.16), in: Capsule())
            .foregroundStyle(.secondary)
    }
}
