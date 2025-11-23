import SwiftUI

struct TermsConditionsView: View {
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
                    Text(NSLocalizedString("TERMS_TITLE", comment: ""))
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

                        TermsCard(
                            title: NSLocalizedString("TERMS_SECTION_ACCEPT_TITLE", comment: ""),
                            icon: "checkmark.seal.fill",
                            items: [
                                String(
                                    format: NSLocalizedString("TERMS_SECTION_ACCEPT_ITEM1", comment: ""),
                                    brandName
                                ),
                                NSLocalizedString("TERMS_SECTION_ACCEPT_ITEM2", comment: "")
                            ],
                            themeManager: themeManager
                        )
                        
                        TermsCard(
                            title: NSLocalizedString("TERMS_SECTION_SERVICE_TITLE", comment: ""),
                            icon: "leaf.fill",
                            items: [
                                String(
                                    format: NSLocalizedString("TERMS_SECTION_SERVICE_ITEM1", comment: ""),
                                    brandName
                                ),
                                NSLocalizedString("TERMS_SECTION_SERVICE_ITEM2", comment: "")
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: NSLocalizedString("TERMS_SECTION_ACCOUNT_TITLE", comment: ""),
                            icon: "person.crop.circle.fill",
                            items: [
                                NSLocalizedString("TERMS_SECTION_ACCOUNT_ITEM1", comment: ""),
                                NSLocalizedString("TERMS_SECTION_ACCOUNT_ITEM2", comment: "")
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: NSLocalizedString("TERMS_SECTION_SUBS_TITLE", comment: ""),
                            icon: "creditcard.fill",
                            items: [
                                NSLocalizedString("TERMS_SECTION_SUBS_ITEM1", comment: ""),
                                NSLocalizedString("TERMS_SECTION_SUBS_ITEM2", comment: ""),
                                NSLocalizedString("TERMS_SECTION_SUBS_ITEM3", comment: "")
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: NSLocalizedString("TERMS_SECTION_TRIALS_TITLE", comment: ""),
                            icon: "clock.badge.checkmark",
                            items: [
                                NSLocalizedString("TERMS_SECTION_TRIALS_ITEM1", comment: ""),
                                NSLocalizedString("TERMS_SECTION_TRIALS_ITEM2", comment: "")
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
                            icon: "hand.raised.fill",
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
                                String(
                                    format: NSLocalizedString("TERMS_SECTION_IP_ITEM1", comment: ""),
                                    brandName
                                ),
                                NSLocalizedString("TERMS_SECTION_IP_ITEM2", comment: "")
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: NSLocalizedString("TERMS_SECTION_PRIVACY_TITLE", comment: ""),
                            icon: "lock.shield.fill",
                            items: [
                                NSLocalizedString("TERMS_SECTION_PRIVACY_ITEM1", comment: ""),
                                NSLocalizedString("TERMS_SECTION_PRIVACY_ITEM2", comment: "")
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: NSLocalizedString("TERMS_SECTION_THIRDPARTY_TITLE", comment: ""),
                            icon: "link.circle.fill",
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
                            icon: "exclamationmark.triangle.fill",
                            items: [
                                String(
                                    format: NSLocalizedString("TERMS_SECTION_LIABILITY_ITEM1", comment: ""),
                                    brandName
                                ),
                                NSLocalizedString("TERMS_SECTION_LIABILITY_ITEM2", comment: "")
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: NSLocalizedString("TERMS_SECTION_INDEMNITY_TITLE", comment: ""),
                            icon: "scales",
                            items: [
                                String(
                                    format: NSLocalizedString("TERMS_SECTION_INDEMNITY_ITEM1", comment: ""),
                                    brandName
                                )
                            ],
                            themeManager: themeManager
                        )

                        TermsCard(
                            title: NSLocalizedString("TERMS_SECTION_LAW_TITLE", comment: ""),
                            icon: "globe.europe.africa.fill",
                            items: [
                                NSLocalizedString("TERMS_SECTION_LAW_ITEM1", comment: ""),
                                NSLocalizedString("TERMS_SECTION_LAW_ITEM2", comment: "")
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
        .interactiveDismissDisabled(false)
    }

    // MARK: - Header
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("TERMS_HEADER_TITLE", comment: ""))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(themeManager.textColor)

            Text(
                String(
                    format: NSLocalizedString("TERMS_HEADER_INTRO", comment: ""),
                    brandName
                )
            )
            .font(.system(size: 14))
            .foregroundColor(themeManager.secondaryTextColor)

            Text(
                String(
                    format: NSLocalizedString("TERMS_LAST_UPDATED", comment: ""),
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
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Contact card
    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
                Text(NSLocalizedString("TERMS_CONTACT_TITLE", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(themeManager.textColor)
                Spacer()
            }
            Text(NSLocalizedString("TERMS_CONTACT_SUBTITLE", comment: ""))
                .font(.system(size: 14))
                .foregroundColor(themeManager.secondaryTextColor)

            Link(destination: URL(string: "mailto:\(contactEmail)")!) {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                    Text(contactEmail)
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.black)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Footer note
    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("TERMS_FOOTER_TITLE", comment: ""))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(themeManager.textColor)

            Text(NSLocalizedString("TERMS_FOOTER_TEXT", comment: ""))
                .font(.system(size: 13))
                .foregroundColor(themeManager.secondaryTextColor)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .padding(.top, 4)
    }
}

// MARK: - Reusable Card
struct TermsCard: View {
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
            RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}
