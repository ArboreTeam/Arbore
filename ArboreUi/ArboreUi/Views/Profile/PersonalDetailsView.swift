import SwiftUI
import FirebaseAuth

struct PersonalDetailsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var fullName: String = ""
    @State private var phoneNumber: String = ""
    @State private var email: String = ""
    @State private var address: String = ""

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

                    inputField(
                        title: NSLocalizedString("PERSONAL_DETAILS_PHONE_LABEL", comment: ""),
                        placeholder: NSLocalizedString("PERSONAL_DETAILS_PHONE_PLACEHOLDER", comment: ""),
                        text: $phoneNumber,
                        systemImage: "phone",
                        keyboardType: .phonePad
                    )

                    inputField(
                        title: NSLocalizedString("PERSONAL_DETAILS_EMAIL_LABEL", comment: ""),
                        placeholder: NSLocalizedString("PERSONAL_DETAILS_EMAIL_PLACEHOLDER", comment: ""),
                        text: $email,
                        systemImage: "envelope",
                        keyboardType: .emailAddress
                    )

                    inputField(
                        title: NSLocalizedString("PERSONAL_DETAILS_ADDRESS_LABEL", comment: ""),
                        placeholder: NSLocalizedString("PERSONAL_DETAILS_ADDRESS_PLACEHOLDER", comment: ""),
                        text: $address,
                        systemImage: "mappin.and.ellipse"
                    )
                }
            }

            Button(action: { dismiss() }) {
                Text(NSLocalizedString("PERSONAL_DETAILS_SAVE_BUTTON", comment: ""))
            }
            .buttonStyle(.arborePrimary)
        }
        .interactiveDismissDisabled()
        .onAppear {
            if let user = Auth.auth().currentUser {
                if fullName.isEmpty { fullName = user.displayName ?? "" }
                if email.isEmpty { email = user.email ?? "" }
                if phoneNumber.isEmpty { phoneNumber = user.phoneNumber ?? "" }
            }
        }
    }
    
    // MARK: - Input Field
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
}

#Preview {
    PersonalDetailsView()
        .environmentObject(ThemeManager())
}
