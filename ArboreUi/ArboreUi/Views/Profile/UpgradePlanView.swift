import SwiftUI

struct UpgradePlanView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedPlan: String = "Premium"

    // MARK: - Plans payants
    let plans: [PlanModel] = [
        PlanModel(
            name: "Premium", // identifiant interne
            price: NSLocalizedString("UPGRADE_PREMIUM_PRICE", comment: ""),
            emoji: "🌼",
            description: NSLocalizedString("UPGRADE_PREMIUM_DESC", comment: ""),
            features: [
                NSLocalizedString("UPGRADE_PREMIUM_FEATURE1", comment: ""),
                NSLocalizedString("UPGRADE_PREMIUM_FEATURE2", comment: ""),
                NSLocalizedString("UPGRADE_PREMIUM_FEATURE3", comment: ""),
                NSLocalizedString("UPGRADE_PREMIUM_FEATURE4", comment: ""),
                NSLocalizedString("UPGRADE_PREMIUM_FEATURE5", comment: ""),
                NSLocalizedString("UPGRADE_PREMIUM_FEATURE6", comment: "")
            ],
            isPopular: true
        ),
        PlanModel(
            name: "Metal",
            price: NSLocalizedString("UPGRADE_METAL_PRICE", comment: ""),
            emoji: "🪙",
            description: NSLocalizedString("UPGRADE_METAL_DESC", comment: ""),
            features: [
                NSLocalizedString("UPGRADE_METAL_FEATURE1", comment: ""),
                NSLocalizedString("UPGRADE_METAL_FEATURE2", comment: ""),
                NSLocalizedString("UPGRADE_METAL_FEATURE3", comment: ""),
                NSLocalizedString("UPGRADE_METAL_FEATURE4", comment: ""),
                NSLocalizedString("UPGRADE_METAL_FEATURE5", comment: "")
            ],
            isPopular: false
        ),
        PlanModel(
            name: "Ultra",
            price: NSLocalizedString("UPGRADE_ULTRA_PRICE", comment: ""),
            emoji: "💎",
            description: NSLocalizedString("UPGRADE_ULTRA_DESC", comment: ""),
            features: [
                NSLocalizedString("UPGRADE_ULTRA_FEATURE1", comment: ""),
                NSLocalizedString("UPGRADE_ULTRA_FEATURE2", comment: ""),
                NSLocalizedString("UPGRADE_ULTRA_FEATURE3", comment: ""),
                NSLocalizedString("UPGRADE_ULTRA_FEATURE4", comment: ""),
                NSLocalizedString("UPGRADE_ULTRA_FEATURE5", comment: "")
            ],
            isPopular: false
        )
    ]

    var body: some View {
        ZStack {
            // Fond qui change selon le plan sélectionné
            backgroundForSelectedPlan(selectedPlan).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(themeManager.textColor)
                    }
                    Spacer()
                    Text(NSLocalizedString("UPGRADE_TITLE", comment: ""))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(themeManager.textColor)
                    Spacer()
                    Color.clear.frame(width: 16)
                }
                .frame(height: 48)
                .padding(.horizontal, 16)

                ScrollView {
                    VStack(spacing: 22) {
                        // Segmented pills
                        PlanSwitcher(selected: $selectedPlan, options: plans.map { $0.name })
                            .padding(.horizontal, 16)
                            .padding(.top, 18)

                        // Carte style Revolut
                        if let current = plans.first(where: { $0.name == selectedPlan }) {
                            RevolutStylePlanCard(
                                plan: current,
                                featureRows: featuresFor(plan: current.name)
                            )
                            .environmentObject(themeManager)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 460)
                        }

                        // CTA
                        if let current = plans.first(where: { $0.name == selectedPlan }) {
                            Button(action: {
                                // TODO: flow d'achat
                                dismiss()
                            }) {
                                Text(ctaButtonLabel(for: current.name))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 28)
                                            .fill(Color.white)
                                    )
                                    .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }

                        // Support
                        VStack(spacing: 8) {
                            Text(NSLocalizedString("UPGRADE_SUPPORT_QUESTION", comment: ""))
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.secondaryTextColor)

                            Link(
                                NSLocalizedString("UPGRADE_SUPPORT_CONTACT", comment: ""),
                                destination: URL(string: "mailto:support@arbore.app") ?? URL(fileURLWithPath: "")
                            )
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.vertical, 24)
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - CTA label
    private func ctaButtonLabel(for plan: String) -> String {
        switch plan {
        case "Premium":
            return NSLocalizedString("UPGRADE_CTA_PREMIUM", comment: "")
        case "Metal":
            return NSLocalizedString("UPGRADE_CTA_METAL", comment: "")
        case "Ultra":
            return NSLocalizedString("UPGRADE_CTA_ULTRA", comment: "")
        default:
            return NSLocalizedString("UPGRADE_CTA_DEFAULT", comment: "")
        }
    }

    // MARK: - Dynamic background
    @ViewBuilder
    private func backgroundForSelectedPlan(_ plan: String) -> some View {
        switch plan {
        case "Premium":
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.10, blue: 0.09),
                    Color(red: 0.03, green: 0.20, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "Metal":
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.09, blue: 0.10),
                    Color(red: 0.16, green: 0.18, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "Ultra":
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.06, blue: 0.12),
                    Color(red: 0.14, green: 0.10, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            themeManager.backgroundColor
        }
    }

    // MARK: - Features avec texte localisé
    private func featuresFor(plan name: String) -> [(String, String)] {
        switch name {
        case "Premium":
            return [
                ("camera.viewfinder", NSLocalizedString("UPGRADE_PREMIUM_FEATUREROW1", comment: "")),
                ("square.grid.2x2", NSLocalizedString("UPGRADE_PREMIUM_FEATUREROW2", comment: "")),
                ("sun.max.and.horizon", NSLocalizedString("UPGRADE_PREMIUM_FEATUREROW3", comment: "")),
                ("paintbrush.pointed.fill", NSLocalizedString("UPGRADE_PREMIUM_FEATUREROW4", comment: "")),
                ("bell.badge.fill", NSLocalizedString("UPGRADE_PREMIUM_FEATUREROW5", comment: "")),
                ("icloud.fill", NSLocalizedString("UPGRADE_PREMIUM_FEATUREROW6", comment: ""))
            ]
        case "Metal":
            return [
                ("cube.fill", NSLocalizedString("UPGRADE_METAL_FEATUREROW1", comment: "")),
                ("leaf.fill", NSLocalizedString("UPGRADE_METAL_FEATUREROW2", comment: "")),
                ("clock.arrow.circlepath", NSLocalizedString("UPGRADE_METAL_FEATUREROW3", comment: "")),
                ("book.closed.fill", NSLocalizedString("UPGRADE_METAL_FEATUREROW4", comment: "")),
                ("bolt.fill", NSLocalizedString("UPGRADE_METAL_FEATUREROW5", comment: ""))
            ]
        case "Ultra":
            return [
                ("map.fill", NSLocalizedString("UPGRADE_ULTRA_FEATUREROW1", comment: "")),
                ("cloud.sun.rain.fill", NSLocalizedString("UPGRADE_ULTRA_FEATUREROW2", comment: "")),
                ("square.and.arrow.up.on.square.fill", NSLocalizedString("UPGRADE_ULTRA_FEATUREROW3", comment: "")),
                ("person.2.fill", NSLocalizedString("UPGRADE_ULTRA_FEATUREROW4", comment: "")),
                ("headphones", NSLocalizedString("UPGRADE_ULTRA_FEATUREROW5", comment: ""))
            ]
        default:
            return []
        }
    }
}

// MARK: - Pills switcher
struct PlanSwitcher: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selected: String
    let options: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { opt in
                Button(action: { selected = opt }) {
                    Text(opt) // "Premium / Metal / Ultra" = noms de plans (brand)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selected == opt ? .black : themeManager.textColor)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 22)
                                .fill(selected == opt ? Color.white : Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22)
                                        .stroke(Color.white.opacity(selected == opt ? 0 : 0.12), lineWidth: 1)
                                )
                        )
                        .shadow(
                            color: selected == opt ? Color.black.opacity(0.12) : .clear,
                            radius: 8, x: 0, y: 4
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Carte style Revolut
struct RevolutStylePlanCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let plan: PlanModel
    let featureRows: [(icon: String, text: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.name) // Nom du plan (Premium / Metal / Ultra)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)

                Text(plan.price.replacingOccurrences(of: " / ", with: "/"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }

            // Feature rows
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(featureRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: row.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 24)

                        Text(row.text)
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - Model
struct PlanModel {
    let name: String          // identifiant / label
    let price: String         // localisé
    let emoji: String
    let description: String   // localisé
    let features: [String]    // localisé (si tu veux les afficher ailleurs)
    let isPopular: Bool
}

#Preview {
    UpgradePlanView()
        .environmentObject(ThemeManager())
}
