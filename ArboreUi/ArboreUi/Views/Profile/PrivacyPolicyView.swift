import SwiftUI

struct PrivacyPolicyView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    private let brandName = "Arbore"
    private let contactEmail = "support@arbore.app"
    private let lastUpdated = "11 Nov 2025"

    var body: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text(NSLocalizedString("PRIVACY_TITLE", comment: "Privacy policy title"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)
                .background(themeManager.backgroundColor)

                ScrollView {
                    VStack(spacing: 18) {
                        headerCard

                        PolicyCard(
                            title: NSLocalizedString("PRIVACY_SECTION_DATA_TITLE", comment: ""),
                            icon: "tray.full.fill",
                            items: [
                                NSLocalizedString("PRIVACY_SECTION_DATA_ITEM1", comment: ""),
                                NSLocalizedString("PRIVACY_SECTION_DATA_ITEM2", comment: ""),
                                NSLocalizedString("PRIVACY_SECTION_DATA_ITEM3", comment: ""),
                                NSLocalizedString("PRIVACY_SECTION_DATA_ITEM4", comment: ""),
                                NSLocalizedString("PRIVACY_SECTION_DATA_ITEM5", comment: "")
                            ],
                            themeManager: themeManager
                        )
                        
                        PolicyCard(
                            title: NSLocalizedString("PRIVACY_SECTION_USAGE_TITLE", comment: ""),
                            icon: "target",
                            items: [
                                String(
                                    format: NSLocalizedString("PRIVACY_SECTION_USAGE_ITEM1", comment: ""),
                                    brandName
                                ),
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
                                String(
                                    format: NSLocalizedString("PRIVACY_SECTION_LEGAL_ITEM2", comment: ""),
                                    brandName
                                ),
                                NSLocalizedString("PRIVACY_SECTION_LEGAL_ITEM3", comment: ""),
                                NSLocalizedString("PRIVACY_SECTION_LEGAL_ITEM4", comment: "")
                            ],
                            themeManager: themeManager
                        )

                        PolicyCard(
                            title: NSLocalizedString("PRIVACY_SECTION_RETENTION_TITLE", comment: ""),
                            icon: "archivebox.fill",
                            items: [
                                NSLocalizedString("PRIVACY_SECTION_RETENTION_ITEM1", comment: ""),
                                NSLocalizedString("PRIVACY_SECTION_RETENTION_ITEM2", comment: "")
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
                            icon: "hand.raised.fill",
                            items: [
                                NSLocalizedString("PRIVACY_SECTION_RIGHTS_ITEM1", comment: ""),
                                NSLocalizedString("PRIVACY_SECTION_RIGHTS_ITEM2", comment: ""),
                                NSLocalizedString("PRIVACY_SECTION_RIGHTS_ITEM3", comment: ""),
                                String(
                                    format: NSLocalizedString("PRIVACY_SECTION_RIGHTS_ITEM4", comment: ""),
                                    contactEmail
                                )
                            ],
                            themeManager: themeManager
                        )

                        PolicyCard(
                            title: NSLocalizedString("PRIVACY_SECTION_SECURITY_TITLE", comment: ""),
                            icon: "lock.shield.fill",
                            items: [
                                NSLocalizedString("PRIVACY_SECTION_SECURITY_ITEM1", comment: ""),
                                NSLocalizedString("PRIVACY_SECTION_SECURITY_ITEM2", comment: ""),
                                NSLocalizedString("PRIVACY_SECTION_SECURITY_ITEM3", comment: "")
                            ],
                            themeManager: themeManager
                        )

                        PolicyCard(
                            title: NSLocalizedString("PRIVACY_SECTION_CHILDREN_TITLE", comment: ""),
                            icon: "person.2.wave.2.fill",
                            items: [
                                String(
                                    format: NSLocalizedString("PRIVACY_SECTION_CHILDREN_ITEM1", comment: ""),
                                    brandName
                                ),
                                NSLocalizedString("PRIVACY_SECTION_CHILDREN_ITEM2", comment: "")
                            ],
                            themeManager: themeManager
                        )

                        PolicyCard(
                            title: NSLocalizedString("PRIVACY_SECTION_TRANSFERS_TITLE", comment: ""),
                            icon: "globe.europe.africa.fill",
                            items: [
                                NSLocalizedString("PRIVACY_SECTION_TRANSFERS_ITEM1", comment: "")
                            ],
                            themeManager: themeManager
                        )

                        contactCard
                        footerNote
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                String(
                    format: NSLocalizedString("PRIVACY_HEADER_TITLE", comment: ""),
                    brandName
                )
            )
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(themeManager.textColor)
            
            Text(NSLocalizedString("PRIVACY_HEADER_SUBTITLE", comment: ""))
                .font(.system(size: 14))
                .foregroundColor(themeManager.secondaryTextColor)
            
            Text(
                String(
                    format: NSLocalizedString("PRIVACY_LAST_UPDATED", comment: ""),
                    lastUpdated
                )
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(themeManager.secondaryTextColor.opacity(0.9))
            .padding(.top, 2)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(themeManager.separatorColor.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Contact card

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
                Text(NSLocalizedString("PRIVACY_CONTACT_TITLE", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.textColor)
                Spacer()
            }
            Text(NSLocalizedString("PRIVACY_CONTACT_SUBTITLE", comment: ""))
                .font(.system(size: 14))
                .foregroundColor(themeManager.secondaryTextColor)

            Link(destination: URL(string: "mailto:\(contactEmail)")!) {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                    Text(contactEmail)
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(themeManager.textColor)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(themeManager.cardBackgroundColor))
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(themeManager.separatorColor.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Footer note

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("PRIVACY_FOOTER_TITLE", comment: ""))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(themeManager.textColor)
            
            Text(NSLocalizedString("PRIVACY_FOOTER_TEXT", comment: ""))
                .font(.system(size: 13))
                .foregroundColor(themeManager.secondaryTextColor)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(themeManager.separatorColor.opacity(0.3), lineWidth: 1)
        )
        .padding(.top, 4)
    }
}

// MARK: - Reusable card

struct PolicyCard: View {
    let title: String
    let icon: String
    let items: [String]
    let themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.green)
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(themeManager.textColor)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.green.opacity(0.9))
                            .padding(.top, 6)
                        Text(item)
                            .font(.system(size: 14))
                            .foregroundColor(themeManager.textColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(themeManager.separatorColor.opacity(0.3), lineWidth: 1)
        )
    }
}
