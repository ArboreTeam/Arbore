import SwiftUI

struct PrivacyPolicyView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    private let brandName = "Arbore"
    private let contactEmail = "support@arbore.app"
    private let lastUpdated = "31 May 2026"

    var body: some View {
        SettingsPage(title: NSLocalizedString("PRIVACY_TITLE", comment: "Privacy policy title")) {
            headerCard

            PolicyCard(
                title: NSLocalizedString("PRIVACY_SECTION_DATA_TITLE", comment: ""),
                icon: "tray.full",
                items: [
                    NSLocalizedString("PRIVACY_SECTION_DATA_ITEM1", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_DATA_ITEM2", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_DATA_ITEM3", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_DATA_ITEM4", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_DATA_ITEM5", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_DATA_ITEM6", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_DATA_ITEM7", comment: "")
                ],
                themeManager: themeManager
            )

            PolicyCard(
                title: NSLocalizedString("PRIVACY_SECTION_USAGE_TITLE", comment: ""),
                icon: "target",
                items: [
                    String(format: NSLocalizedString("PRIVACY_SECTION_USAGE_ITEM1", comment: ""), brandName),
                    NSLocalizedString("PRIVACY_SECTION_USAGE_ITEM2", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_USAGE_ITEM3", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_USAGE_ITEM4", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_USAGE_ITEM5", comment: "")
                ],
                themeManager: themeManager
            )

            PolicyCard(
                title: NSLocalizedString("PRIVACY_SECTION_LEGAL_TITLE", comment: ""),
                icon: "doc.text.magnifyingglass",
                items: [
                    NSLocalizedString("PRIVACY_SECTION_LEGAL_ITEM1", comment: ""),
                    String(format: NSLocalizedString("PRIVACY_SECTION_LEGAL_ITEM2", comment: ""), brandName),
                    NSLocalizedString("PRIVACY_SECTION_LEGAL_ITEM3", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_LEGAL_ITEM4", comment: "")
                ],
                themeManager: themeManager
            )

            PolicyCard(
                title: NSLocalizedString("PRIVACY_SECTION_RETENTION_TITLE", comment: ""),
                icon: "archivebox",
                items: [
                    NSLocalizedString("PRIVACY_SECTION_RETENTION_ITEM1", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_RETENTION_ITEM2", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_RETENTION_ITEM3", comment: "")
                ],
                themeManager: themeManager
            )

            PolicyCard(
                title: NSLocalizedString("PRIVACY_SECTION_SHARING_TITLE", comment: ""),
                icon: "arrow.2.squarepath",
                items: [
                    NSLocalizedString("PRIVACY_SECTION_SHARING_ITEM1", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_SHARING_ITEM2", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_SHARING_ITEM3", comment: "")
                ],
                themeManager: themeManager
            )

            PolicyCard(
                title: NSLocalizedString("PRIVACY_SECTION_RIGHTS_TITLE", comment: ""),
                icon: "hand.raised",
                items: [
                    NSLocalizedString("PRIVACY_SECTION_RIGHTS_ITEM1", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_RIGHTS_ITEM2", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_RIGHTS_ITEM3", comment: ""),
                    String(format: NSLocalizedString("PRIVACY_SECTION_RIGHTS_ITEM4", comment: ""), contactEmail)
                ],
                themeManager: themeManager
            )

            PolicyCard(
                title: NSLocalizedString("PRIVACY_SECTION_SECURITY_TITLE", comment: ""),
                icon: "lock.shield",
                items: [
                    NSLocalizedString("PRIVACY_SECTION_SECURITY_ITEM1", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_SECURITY_ITEM2", comment: ""),
                    NSLocalizedString("PRIVACY_SECTION_SECURITY_ITEM3", comment: "")
                ],
                themeManager: themeManager
            )

            PolicyCard(
                title: NSLocalizedString("PRIVACY_SECTION_CHILDREN_TITLE", comment: ""),
                icon: "person.2.wave.2",
                items: [
                    String(format: NSLocalizedString("PRIVACY_SECTION_CHILDREN_ITEM1", comment: ""), brandName),
                    NSLocalizedString("PRIVACY_SECTION_CHILDREN_ITEM2", comment: "")
                ],
                themeManager: themeManager
            )

            PolicyCard(
                title: NSLocalizedString("PRIVACY_SECTION_TRANSFERS_TITLE", comment: ""),
                icon: "globe.europe.africa",
                items: [
                    NSLocalizedString("PRIVACY_SECTION_TRANSFERS_ITEM1", comment: "")
                ],
                themeManager: themeManager
            )

            contactCard
            footerNote
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Header

    private var headerCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
            Text(
                String(
                    format: NSLocalizedString("PRIVACY_HEADER_TITLE", comment: ""),
                    brandName
                )
            )
            .font(ArboreDesign.Typography.sectionTitle)
            .foregroundColor(ArboreDesign.Colors.textPrimary)
            
            Text(NSLocalizedString("PRIVACY_HEADER_SUBTITLE", comment: ""))
                .font(ArboreDesign.Typography.bodySmall)
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(
                String(
                    format: NSLocalizedString("PRIVACY_LAST_UPDATED", comment: ""),
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
            title: NSLocalizedString("PRIVACY_CONTACT_TITLE", comment: ""),
            systemImage: "envelope"
        ) {
            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
            Text(NSLocalizedString("PRIVACY_CONTACT_SUBTITLE", comment: ""))
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
            Text(NSLocalizedString("PRIVACY_FOOTER_TITLE", comment: ""))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.textPrimary)
            
            Text(NSLocalizedString("PRIVACY_FOOTER_TEXT", comment: ""))
                .font(ArboreDesign.Typography.caption)
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Reusable card

struct PolicyCard: View {
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
