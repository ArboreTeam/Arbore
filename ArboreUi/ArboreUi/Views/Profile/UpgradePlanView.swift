import SwiftUI

/// Kept as a standalone destination for backwards-compatible navigation.
/// Arbore has no paid tier or in-app purchase: every currently available
/// feature belongs to the single free plan.
struct UpgradePlanView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                SettingsTopBar(title: L10n.t("PLAN_TITLE_STANDARD")) {
                    dismiss()
                }

                ScrollView {
                    AppCard {
                        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.lg) {
                            SettingsIconBadge(
                                systemImage: "leaf.fill",
                                tint: ArboreDesign.Colors.primaryGreen,
                                size: 58
                            )

                            Text(L10n.t("PLAN_TITLE_STANDARD"))
                                .font(ArboreDesign.Typography.pageTitle)
                                .foregroundColor(ArboreDesign.Colors.textPrimary)

                            Text(L10n.t("SUBSCRIPTION_DESCRIPTION_STANDARD"))
                                .font(ArboreDesign.Typography.body)
                                .foregroundColor(ArboreDesign.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Label(L10n.t("PLAN_FREE"), systemImage: "checkmark.seal.fill")
                                .font(ArboreDesign.Typography.cardTitle)
                                .foregroundColor(ArboreDesign.Colors.primaryGreen)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
                    .padding(.top, ArboreDesign.Spacing.xl)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

#Preview {
    UpgradePlanView()
        .environmentObject(ThemeManager())
}
