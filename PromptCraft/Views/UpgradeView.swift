import SwiftUI

// MARK: - UpgradeView

struct UpgradeView: View {
    var onBack: () -> Void

    @ObservedObject private var licensingService = LicensingService.shared
    @ObservedObject private var trialService = TrialService.shared
    @ObservedObject private var contextEngine = ContextEngineService.shared

    @State private var licenseKeyText: String = ""
    @State private var isActivating: Bool = false
    @State private var activationMessage: String?
    @State private var activationSuccess: Bool = false
    @State private var isAnnualBilling: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            upgradeHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    contextHeadline
                    proCard
                    cloudCard
                    preservationMessage
                    licenseEntrySection
                    restoreSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Header

    private var upgradeHeader: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Upgrade")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: - Context Headline

    private var contextHeadline: some View {
        Group {
            if contextEngine.entryCount > 0 {
                Text("Your \(contextEngine.entryCount) learned patterns from \(contextEngine.clusters.count) project\(contextEngine.clusters.count == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            } else {
                Text("Unlock the full power of PromptCraft")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Pro Card

    private var proCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                Text("Pro")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("$24.99")
                    .font(.system(size: 16, weight: .bold))
                Text("one-time")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text("Bring your own API key. All features. Forever.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                featureBullet("Unlimited optimizations")
                featureBullet("Context engine + history")
                featureBullet("Custom styles & templates")
                featureBullet("All future updates")
            }

            Button(action: {
                if let url = URL(string: AppConstants.CloudAPI.proCheckoutURL) {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text("Get Pro")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Cloud Card

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
                Text("Cloud")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    if isAnnualBilling {
                        HStack(spacing: 2) {
                            Text("$59")
                                .font(.system(size: 16, weight: .bold))
                            Text("/yr")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Text("$4.92/mo")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 2) {
                            Text("$7.99")
                                .font(.system(size: 16, weight: .bold))
                            Text("/mo")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Text("Built-in AI. No API key needed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Picker("Billing", selection: $isAnnualBilling) {
                Text("Monthly").tag(false)
                Text("Annual (Save 38%)").tag(true)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                featureBullet("Everything in Pro")
                featureBullet("Built-in AI, no API key setup")
                featureBullet("Optimized models for prompt engineering")
                featureBullet("Priority support")
            }

            Button(action: {
                let checkoutURL = isAnnualBilling
                    ? AppConstants.CloudAPI.cloudAnnualCheckoutURL
                    : AppConstants.CloudAPI.cloudMonthlyCheckoutURL
                if let url = URL(string: checkoutURL) {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text("Get Cloud")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Preservation Message

    private var preservationMessage: some View {
        Group {
            if contextEngine.entryCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    Text("Your \(contextEngine.entryCount) context entries and all history will be preserved when you upgrade.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.green.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - License Entry

    private var licenseEntrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Have a license key?")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                SecureField("Enter license key...", text: $licenseKeyText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Button(action: activateLicense) {
                    if isActivating {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    } else {
                        Text("Activate")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .disabled(licenseKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isActivating)
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .foregroundStyle(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let msg = activationMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(activationSuccess ? .green : .red)
            }
        }
    }

    // MARK: - Restore

    private var restoreSection: some View {
        Button(action: {
            if let url = URL(string: AppConstants.CloudAPI.restorePurchaseURL) {
                NSWorkspace.shared.open(url)
            }
        }) {
            Text("Restore Purchase")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.deepLinkActivation)) { notification in
            if let key = notification.userInfo?["key"] as? String {
                licenseKeyText = key
                activateLicense()
            }
        }
    }

    // MARK: - Helpers

    private func featureBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.green)
                .frame(width: 14)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
        }
    }

    private func activateLicense() {
        let key = licenseKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        isActivating = true
        activationMessage = nil

        Task {
            let success = await licensingService.activateLicense(key: key)
            await MainActor.run {
                isActivating = false
                activationSuccess = success
                if success {
                    activationMessage = "License activated successfully!"
                } else {
                    activationMessage = licensingService.validationError ?? "Invalid license key."
                }
            }
        }
    }
}
