import SwiftUI
import FirebaseAuth

struct PersonalDetailsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    @State private var fullName: String = ""
    @State private var email: String = ""
    @State private var initialName: String = ""
    @State private var avoidPetToxicity = false
    @State private var avoidChildToxicity = false
    @State private var initialHouseholdSafety = HouseholdSafetyProfile(
        avoidPetToxicity: false,
        avoidChildToxicity: false
    )

    @State private var isSaving: Bool = false
    @State private var isLoadingProfile: Bool = false
    @State private var errorMessage: String? = nil
    @State private var didSave: Bool = false

    private var trimmedName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !isSaving
            && !isLoadingProfile
            && !trimmedName.isEmpty
            && (
                trimmedName != initialName
                    || avoidPetToxicity != initialHouseholdSafety.avoidPetToxicity
                    || avoidChildToxicity != initialHouseholdSafety.avoidChildToxicity
            )
    }

    var body: some View {
        SettingsPage(title: NSLocalizedString("PERSONAL_DETAILS_TITLE", comment: "")) {
            SettingsSectionCard(
                title: NSLocalizedString("PERSONAL_DETAILS_TITLE", comment: ""),
                systemImage: "person.crop.circle"
            ) {
                VStack(spacing: ArboreDesign.Spacing.md) {
                    inputField(
                        title: NSLocalizedString("PERSONAL_DETAILS_FULLNAME_LABEL", comment: ""),
                        placeholder: NSLocalizedString("PERSONAL_DETAILS_FULLNAME_PLACEHOLDER", comment: ""),
                        text: $fullName,
                        systemImage: "person"
                    )
                    .disabled(isSaving)

                    readOnlyField(
                        title: NSLocalizedString("PERSONAL_DETAILS_EMAIL_LABEL", comment: ""),
                        value: email.isEmpty ? "—" : email,
                        systemImage: "envelope"
                    )
                }
            }

            SettingsSectionCard(
                title: NSLocalizedString("PERSONAL_DETAILS_SAFETY_TITLE", comment: ""),
                systemImage: "checkmark.shield"
            ) {
                Text(NSLocalizedString("PERSONAL_DETAILS_SAFETY_SUBTITLE", comment: ""))
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                safetyToggleRow(
                    title: NSLocalizedString("PERSONAL_DETAILS_SAFETY_PETS", comment: ""),
                    systemImage: "pawprint",
                    isOn: $avoidPetToxicity
                )

                Divider()

                safetyToggleRow(
                    title: NSLocalizedString("PERSONAL_DETAILS_SAFETY_CHILDREN", comment: ""),
                    systemImage: "figure.and.child.holdinghands",
                    isOn: $avoidChildToxicity
                )
            }
            .disabled(isSaving || isLoadingProfile)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(ArboreDesign.Typography.caption)
                    .foregroundColor(ArboreDesign.Colors.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ArboreDesign.Spacing.lg)
            }

            if didSave && errorMessage == nil {
                Text(NSLocalizedString("PERSONAL_DETAILS_SAVE_SUCCESS", comment: ""))
                    .font(ArboreDesign.Typography.caption)
                    .foregroundColor(ArboreDesign.Colors.success)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ArboreDesign.Spacing.lg)
            }

            Button(action: save) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(NSLocalizedString("PERSONAL_DETAILS_SAVE_BUTTON", comment: ""))
                }
            }
            .buttonStyle(.arborePrimary)
            .disabled(!canSave)
            .opacity(canSave ? 1.0 : 0.5)
        }
        .interactiveDismissDisabled(isSaving)
        .onAppear {
            if let user = Auth.auth().currentUser {
                if fullName.isEmpty { fullName = user.displayName ?? "" }
                if email.isEmpty { email = user.email ?? "" }
                initialName = fullName
            }
        }
        .task {
            await loadProfile()
        }
    }

    // MARK: - Save action

    private func save() {
        let payload = trimmedName
        errorMessage = nil
        didSave = false
        isSaving = true

        Task {
            do {
                let _: UserResponse = try await NetworkManager.shared.request(
                    endpoint: "/users/me",
                    method: .PATCH,
                    body: [
                        "name": payload,
                        "householdSafety": [
                            "avoidPetToxicity": avoidPetToxicity,
                            "avoidChildToxicity": avoidChildToxicity
                        ]
                    ]
                )
                await updateFirebaseDisplayName(payload)

                await MainActor.run {
                    self.initialName = payload
                    self.initialHouseholdSafety = HouseholdSafetyProfile(
                        avoidPetToxicity: avoidPetToxicity,
                        avoidChildToxicity: avoidChildToxicity
                    )
                    self.didSave = true
                    self.isSaving = false
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    self.isSaving = false
                    self.errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? NSLocalizedString("PERSONAL_DETAILS_SAVE_ERROR", comment: "")
                }
            }
        }
    }

    private func loadProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await MainActor.run {
            isLoadingProfile = true
        }
        do {
            let response: UserResponse = try await NetworkManager.shared.request(
                endpoint: "/users/\(uid)",
                method: .GET
            )
            await MainActor.run {
                if let user = response.user {
                    fullName = user.name
                    initialName = user.name
                    let safety = user.householdSafety ?? HouseholdSafetyProfile(
                        avoidPetToxicity: false,
                        avoidChildToxicity: false
                    )
                    avoidPetToxicity = safety.avoidPetToxicity
                    avoidChildToxicity = safety.avoidChildToxicity
                    initialHouseholdSafety = safety
                }
                isLoadingProfile = false
            }
        } catch {
            await MainActor.run {
                isLoadingProfile = false
                errorMessage = NSLocalizedString("PERSONAL_DETAILS_LOAD_ERROR", comment: "")
            }
        }
    }

    private func updateFirebaseDisplayName(_ newName: String) async {
        guard let user = Auth.auth().currentUser, user.displayName != newName else { return }
        let change = user.createProfileChangeRequest()
        change.displayName = newName
        try? await change.commitChanges()
    }

    // MARK: - Input fields

    private func inputField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        systemImage: String,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(ArboreDesign.Typography.caption)
                .foregroundColor(ArboreDesign.Colors.textSecondary)

            AppTextField(
                text: text,
                placeholder: placeholder,
                systemImage: systemImage,
                keyboardType: keyboardType
            )
        }
    }

    private func readOnlyField(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(ArboreDesign.Typography.caption)
                .foregroundColor(ArboreDesign.Colors.textSecondary)

            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                Text(value)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                Spacer()
            }
            .padding()
            .background(ArboreDesign.Colors.card.opacity(0.5))
            .cornerRadius(ArboreDesign.Radius.medium)
        }
    }

    private func safetyToggleRow(
        title: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                .frame(width: 24)
            Text(title)
                .font(ArboreDesign.Typography.body)
                .foregroundColor(ArboreDesign.Colors.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(ArboreDesign.Colors.primaryGreen)
        }
    }
}

#Preview {
    PersonalDetailsView()
        .environmentObject(ThemeManager())
}
