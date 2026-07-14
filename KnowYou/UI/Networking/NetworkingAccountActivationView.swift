import SwiftUI

struct NetworkingAccountActivationView: View {
    let phase: NetworkingAccountActivationPhase
    let errorMessage: String?
    let warningMessage: String?
    let isDeviceListReliable: Bool
    let currentDeviceID: String?
    let isWorking: Bool
    let onBegin: () -> Void
    let onRequestOTP: (String) -> Void
    let onVerifyOTP: (String, String) -> Void
    let onApproveProfile: () -> Void
    let onAuthorizeDevice: (String) -> Void
    let onRevokeDevice: (String) -> Void
    let onRefreshDevices: () -> Void
    let onContinue: () -> Void

    @State private var email = ""
    @State private var otp = ""
    @State private var deviceName = Host.current().localizedName ?? "My Mac"
    @FocusState private var focusedField: Field?
    @AccessibilityFocusState private var focusedAnnouncement: Announcement?

    private enum Field { case email, otp, deviceName }
    private enum Announcement: Hashable { case error, warning }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if phase.progressStep > 0 {
                progress
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title2.weight(.bold))
                Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            phaseContent
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("networking-activation-error")
                    .accessibilityFocused($focusedAnnouncement, equals: .error)
            }
            if let warningMessage {
                Label(warningMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("networking-activation-warning")
                    .accessibilityFocused($focusedAnnouncement, equals: .warning)
            }
            Text(phase.privacyCopy)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(28)
        .frame(maxWidth: 620, alignment: .leading)
        .accessibilityIdentifier("networking-account-activation")
        .onAppear {
            focusCurrentField()
            Task { @MainActor in
                await Task.yield()
                focusCurrentAnnouncement()
            }
        }
        .onChange(of: phase.progressStep) { _, _ in focusCurrentField() }
        .onChange(of: errorMessage) { _, value in
            if value != nil { focusedAnnouncement = .error }
        }
        .onChange(of: warningMessage) { _, value in
            if value != nil, errorMessage == nil { focusedAnnouncement = .warning }
        }
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { step in
                Capsule()
                    .fill(step <= phase.progressStep ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(height: 5)
            }
        }
        .accessibilityLabel("Activation step \(phase.progressStep) of 5")
    }

    @ViewBuilder private var phaseContent: some View {
        switch phase {
        case .introduction:
            introductionContent
        case .email:
            TextField("Email address", text: $email)
                .textContentType(.emailAddress)
                .focused($focusedField, equals: .email)
                .onSubmit {
                    if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        requestOTP()
                    }
                }
            primaryButton("Send verification code", action: requestOTP, disabled: email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case let .otp(sentEmail):
            Text("Code sent to \(sentEmail)").font(.callout.weight(.medium))
            TextField("6-digit code", text: $otp)
                .textContentType(.oneTimeCode)
                .focused($focusedField, equals: .otp)
                .onChange(of: otp) { _, value in otp = NetworkingAccountActivationPresentation.normalizedOTP(value) }
                .onSubmit { verifyOTP(email: sentEmail) }
                .accessibilityLabel("Six digit email verification code")
            primaryButton("Verify email", action: { verifyOTP(email: sentEmail) }, disabled: !NetworkingAccountActivationPresentation.isValidOTP(otp))
            Button("Resend code") { onRequestOTP(sentEmail) }
                .disabled(isWorking)
            Button("Use a different email") { email = ""; otp = ""; onRequestOTP("") }
                .disabled(isWorking)
        case .profileApproval:
            Label("Your name, selected profile summary, and approved posts can appear publicly.", systemImage: "person.text.rectangle")
            Label("Diary entries, raw My Wiki pages, and private agent reasoning never leave this Mac.", systemImage: "lock.fill")
            primaryButton("Approve public profile", action: onApproveProfile)
        case let .deviceAuthorization(activeDevices):
            TextField("Device name", text: $deviceName)
                .focused($focusedField, equals: .deviceName)
            Text(NetworkingAccountActivationPresentation.deviceCapacityMessage(
                activeCount: activeDevices.count,
                isReliable: isDeviceListReliable,
                isReauthorizingExistingDevice: isReauthorizingExistingDevice(activeDevices)
            ))
                .font(.callout)
                .foregroundStyle(
                    (activeDevices.count >= 3 && isReauthorizingExistingDevice(activeDevices) == false)
                        || isDeviceListReliable == false
                        ? .red
                        : .secondary
                )
            ForEach(activeDevices, id: \.id) { device in
                HStack {
                    Image(systemName: "laptopcomputer")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.displayName).font(.callout.weight(.medium))
                        Text("Active device").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Revoke", role: .destructive) { onRevokeDevice(device.deviceID) }
                        .disabled(isWorking)
                        .accessibilityLabel("Revoke \(device.displayName)")
                }
                .padding(.vertical, 4)
            }
            if isDeviceListReliable == false {
                Button("Retry loading devices", action: onRefreshDevices)
                    .disabled(isWorking)
            }
            primaryButton(
                "Authorize this Mac",
                action: { onAuthorizeDevice(deviceName) },
                disabled: NetworkingAccountActivationPresentation.canAuthorizeDevice(
                    activeCount: activeDevices.count,
                    isReliable: isDeviceListReliable,
                    deviceName: deviceName,
                    isReauthorizingExistingDevice: isReauthorizingExistingDevice(activeDevices)
                ) == false
            )
        case .sessionRecovery:
            Label("Your account is still connected on this Mac.", systemImage: "wifi.exclamationmark")
            Text("KnowYou could not reach Networking. Your saved credentials were not removed.")
                .foregroundStyle(.secondary)
            primaryButton("Retry connection", action: onContinue)
        case .ready:
            Label("Networking is ready", systemImage: "checkmark.seal.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)
            primaryButton("Enter Networking", action: onContinue)
        }
    }

    private func isReauthorizingExistingDevice(_ activeDevices: [NetworkingDeviceRecord]) -> Bool {
        guard let currentDeviceID, currentDeviceID.isEmpty == false else { return false }
        return activeDevices.contains { $0.deviceID == currentDeviceID }
    }

    private var introductionContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ForEach(NetworkingAccountActivationIntroduction.presentation.destinations, id: \.title) { destination in
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: destination.systemImage)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(destination.title == "Friends" ? Color.black : Color.white)
                            .frame(width: 42, height: 42)
                            .background(destination.title == "Friends" ? Color.yellow : Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(destination.title).font(.headline)
                        Text(destination.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.18))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Label(NetworkingAccountActivationIntroduction.presentation.registrationReason, systemImage: "envelope.badge.shield.half.filled")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            primaryButton("Set up Networking", action: onBegin)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void, disabled: Bool = false) -> some View {
        Button(action: action) {
            HStack {
                if isWorking { ProgressView().controlSize(.small) }
                Text(title)
                Spacer()
                Image(systemName: "arrow.right")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(disabled || isWorking)
    }

    private var title: String {
        switch phase {
        case .introduction: "Your agent can network for you"
        case .email: "Connect your Networking account"
        case .otp: "Check your email"
        case .profileApproval: "Choose what becomes public"
        case .deviceAuthorization: "Authorize this Mac"
        case .sessionRecovery: "Networking is temporarily unavailable"
        case .ready: "You are connected"
        }
    }

    private var subtitle: String {
        switch phase {
        case .introduction: "Explore two distinct communities while KnowYou keeps you in control of every public identity and post."
        case .email: "Use an email you can access. We will send a six-digit code."
        case .otp: "The code expires after 10 minutes. You can paste it directly."
        case .profileApproval: "KnowYou asks before publishing identity or profile information."
        case .deviceAuthorization: "Each device has its own credential and can be revoked independently."
        case .sessionRecovery: "Retry when your internet connection or the Networking service is available."
        case .ready: "Your verified identity is shared across Friends and Career."
        }
    }

    private func requestOTP() {
        onRequestOTP(email.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func verifyOTP(email: String) {
        onVerifyOTP(email, otp)
    }

    private func focusCurrentField() {
        switch phase {
        case .introduction: focusedField = nil
        case .email: focusedField = .email
        case .otp: focusedField = .otp
        case .deviceAuthorization: focusedField = .deviceName
        case .sessionRecovery: focusedField = nil
        default: focusedField = nil
        }
    }

    private func focusCurrentAnnouncement() {
        if errorMessage != nil {
            focusedAnnouncement = .error
        } else if warningMessage != nil {
            focusedAnnouncement = .warning
        }
    }
}
