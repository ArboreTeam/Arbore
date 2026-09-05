import SwiftUI

struct TermsConditionsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    private let brandName = "Arbore"
    private let contactEmail = "support@arbore.app"
    private var lastUpdated: String {
        NSLocalizedString("TERMS_LAST_UPDATED_DATE", comment: "")
    }

    var body: some View {
        SettingsPage(title: NSLocalizedString("TERMS_TITLE", comment: "")) {
            headerCard

            TermsCard(
                title: NSLocalizedString("TERMS_SECTION_ACCEPT_TITLE", comment: ""),
                icon: "checkmark.seal",
                items: [
                    String(format: NSLocalizedString("TERMS_SECTION_ACCEPT_ITEM1", comment: ""), brandName),
                    NSLocalizedString("TERMS_SECTION_ACCEPT_ITEM2", comment: "")
                ],
                themeManager: themeManager
            )

            TermsCard(
                title: NSLocalizedString("TERMS_SECTION_SERVICE_TITLE", comment: ""),
                icon: "leaf",
                items: [
                    String(format: NSLocalizedString("TERMS_SECTION_SERVICE_ITEM1", comment: ""), brandName),
                    NSLocalizedString("TERMS_SECTION_SERVICE_ITEM2", comment: "")
                ],
                themeManager: themeManager
            )

            TermsCard(
                title: NSLocalizedString("TERMS_SECTION_ACCOUNT_TITLE", comment: ""),
                icon: "person.crop.circle",
                items: [
                    NSLocalizedString("TERMS_SECTION_ACCOUNT_ITEM1", comment: ""),
                    NSLocalizedString("TERMS_SECTION_ACCOUNT_ITEM2", comment: "")
                ],
                themeManager: themeManager
            )

            TermsCard(
                title: NSLocalizedString("TERMS_SECTION_USERCONTENT_TITLE", comment: ""),
                icon: "photo.on.rectangle.angled",
                items: [
                    NSLocalizedString("TERMS_SECTION_USERCONTENT_ITEM1", comment: ""),
                    NSLocalizedString("TERMS_SECTION_USERCONTENT_ITEM2", comment: ""),
                    NSLocalizedString("TERMS_SECTION_USERCONTENT_ITEM3", comment: "")
                ],
                themeManager: themeManager
            )

            TermsCard(
                title: NSLocalizedString("TERMS_SECTION_FORBIDDEN_TITLE", comment: ""),
                icon: "hand.raised",
                items: [
                    NSLocalizedString("TERMS_SECTION_FORBIDDEN_ITEM1", comment: ""),
                    NSLocalizedString("TERMS_SECTION_FORBIDDEN_ITEM2", comment: ""),
                    NSLocalizedString("TERMS_SECTION_FORBIDDEN_ITEM3", comment: "")
                ],
                themeManager: themeManager
            )

            TermsCard(
                title: NSLocalizedString("TERMS_SECTION_IP_TITLE", comment: ""),
                icon: "shield.lefthalf.filled",
                items: [
                    String(format: NSLocalizedString("TERMS_SECTION_IP_ITEM1", comment: ""), brandName),
                    NSLocalizedString("TERMS_SECTION_IP_ITEM2", comment: "")
                ],
                themeManager: themeManager
            )

            TermsCard(
                title: NSLocalizedString("TERMS_SECTION_PRIVACY_TITLE", comment: ""),
                icon: "lock.shield",
                items: [
                    NSLocalizedString("TERMS_SECTION_PRIVACY_ITEM1", comment: ""),
                    NSLocalizedString("TERMS_SECTION_PRIVACY_ITEM2", comment: "")
                ],
                themeManager: themeManager
            )

            TermsCard(
                title: NSLocalizedString("TERMS_SECTION_THIRDPARTY_TITLE", comment: ""),
                icon: "link.circle",
                items: [
                    NSLocalizedString("TERMS_SECTION_THIRDPARTY_ITEM1", comment: ""),
                    NSLocalizedString("TERMS_SECTION_THIRDPARTY_ITEM2", comment: "")
                ],
                themeManager: themeManager
            )

            TermsCard(
                title: NSLocalizedString("TERMS_SECTION_AVAILABILITY_TITLE", comment: ""),
                icon: "antenna.radiowaves.left.and.right",
                items: [
                    NSLocalizedString("TERMS_SECTION_AVAILABILITY_ITEM1", comment: ""),
                    NSLocalizedString("TERMS_SECTION_AVAILABILITY_ITEM2", comment: "")
                ],
                themeManager: themeManager
            )

            TermsCard(
                title: NSLocalizedString("TERMS_SECTION_LIABILITY_TITLE", comment: ""),
                icon: "exclamationmark.triangle",
                items: [
                    String(format: NSLocalizedString("TERMS_SECTION_LIABILITY_ITEM1", comment: ""), brandName),
                    NSLocalizedString("TERMS_SECTION_LIABILITY_ITEM2", comment: "")
                ],
                themeManager: themeManager
            )

            TermsCard(
                title: NSLocalizedString("TERMS_SECTION_INDEMNITY_TITLE", comment: ""),
                icon: "scales",
                items: [
                    String(format: NSLocalizedString("TERMS_SECTION_INDEMNITY_ITEM1", comment: ""), brandName)
                ],
                themeManager: themeManager
            )

            TermsCard(
                title: NSLocalizedString("TERMS_SECTION_LAW_TITLE", comment: ""),
                icon: "globe.europe.africa",
                items: [
                    NSLocalizedString("TERMS_SECTION_LAW_ITEM1", comment: ""),
                    NSLocalizedString("TERMS_SECTION_LAW_ITEM2", comment: "")
                ],
                themeManager: themeManager
            )

            contactCard
            footerNote
        }
        .interactiveDismissDisabled(false)
    }

    // MARK: - Header
    private var headerCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
            Text(NSLocalizedString("TERMS_HEADER_TITLE", comment: ""))
                .font(ArboreDesign.Typography.sectionTitle)
                .foregroundColor(ArboreDesign.Colors.textPrimary)

            Text(
                String(
                    format: NSLocalizedString("TERMS_HEADER_INTRO", comment: ""),
                    brandName
                )
            )
            .font(ArboreDesign.Typography.bodySmall)
            .foregroundColor(ArboreDesign.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Text(
                String(
                    format: NSLocalizedString("TERMS_LAST_UPDATED", comment: ""),
                    lastUpdated
                )
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(ArboreDesign.Colors.textMuted)
            .padding(.top, 2)
            }
        }
    }

    // MARK: - Contact card
    private var contactCard: some View {
        SettingsSectionCard(
            title: NSLocalizedString("TERMS_CONTACT_TITLE", comment: ""),
            systemImage: "envelope"
        ) {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
            Text(NSLocalizedString("TERMS_CONTACT_SUBTITLE", comment: ""))
                .font(ArboreDesign.Typography.bodySmall)
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: URL(string: "mailto:\(contactEmail)")!) {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane")
                    Text(contactEmail)
                }
            }
            .buttonStyle(.arboreSecondary)
            }
        }
    }

    // MARK: - Footer note
    private var footerNote: some View {
        AppCard {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
            Text(NSLocalizedString("TERMS_FOOTER_TITLE", comment: ""))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.textPrimary)

            Text(NSLocalizedString("TERMS_FOOTER_TEXT", comment: ""))
                .font(ArboreDesign.Typography.caption)
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Reusable Card
struct TermsCard: View {
    let title: String
    let icon: String
    let items: [String]
    let themeManager: ThemeManager

    var body: some View {
        SettingsSectionCard(title: title, systemImage: icon) {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: ArboreDesign.Spacing.xs) {
                        Circle()
                            .fill(ArboreDesign.Colors.primaryGreen)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)

                        Text(item)
                            .font(ArboreDesign.Typography.bodySmall)
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
