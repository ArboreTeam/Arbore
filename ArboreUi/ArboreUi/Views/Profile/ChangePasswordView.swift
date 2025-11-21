import SwiftUI

struct ChangePasswordView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""

    var body: some View {
        ZStack {
            Color(hex: "#1A1A1A")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with close button (same pattern as PersonalDetailsView / UpgradePlanView)
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text("Change Password")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(Color(hex: "#1A1A1A"))

                // Content
                ScrollView {
                    VStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CURRENT PASSWORD")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .padding(.horizontal, 16)

                            SecureField("Enter current password", text: $currentPassword)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(Color(hex: "#2A2A2A"))
                                .cornerRadius(10)
                                .padding(.horizontal, 16)
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("NEW PASSWORD")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(themeManager.secondaryTextColor)
                                .padding(.horizontal, 16)

                            SecureField("Enter new password", text: $newPassword)
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(Color(hex: "#2A2A2A"))
                                .cornerRadius(10)
                                .padding(.horizontal, 16)

                            SecureField("Confirm new password", text: $confirmPassword)
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(Color(hex: "#2A2A2A"))
                                .cornerRadius(10)
                                .padding(.horizontal, 16)
                        }

                        Spacer(minLength: 8)

                        Button(action: {
                            // Logic to change password
                            dismiss()
                        }) {
                            Text("Update Password")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "#263826"))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                                .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 24)
                    }
                    .padding(.top, 18)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

#Preview {
    ChangePasswordView()
        .environmentObject(ThemeManager())
}