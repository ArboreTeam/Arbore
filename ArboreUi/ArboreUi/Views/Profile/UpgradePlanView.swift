import SwiftUI

struct UpgradePlanView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedPlan: String = "Premium"

    // MARK: - 3 plans payants
    let plans: [PlanModel] = [
        PlanModel(
            name: "Premium",
            price: "4,99 € / mois",
            emoji: "🌼",
            description: "Tout pour concevoir et entretenir sans friction",
            features: [
                "Scans illimités pour identifier instantanément vos plantes.",
                "Projets multiples pour chaque espace (jardin, terrasse, intérieur).",
                "Placement intelligent : recommandations par ensoleillement et compatibilités.",
                "Styles exclusifs pour des compositions harmonieuses.",
                "Notifications intelligentes selon météo et saison.",
                "Synchronisation sécurisée entre vos appareils."
            ],
            isPopular: true
        ),
        PlanModel(
            name: "Metal",
            price: "9,99 € / mois",
            emoji: "🪙",
            description: "Précision et puissance pour les exigences élevées",
            features: [
                "Plans 3D plus détaillés avec calques d’aménagement.",
                "Conseils d’entretien avancés personnalisés par espèce.",
                "Historique de croissance et suivi des interventions.",
                "Bibliothèque premium d’espèces et de styles.",
                "Analyses et traitements prioritaires."
            ],
            isPopular: false
        ),
        PlanModel(
            name: "Ultra",
            price: "14,99 € / mois",
            emoji: "💎",
            description: "L’expérience complète pour viser l’excellence",
            features: [
                "Guides d’aménagement étape-par-étape, du plan à la réalisation.",
                "Assistant météo proactif avec recommandations automatiques.",
                "Exports HD (visuels & listes) pour achats et partage.",
                "Mode collaboration (lecture) pour avis et validation.",
                "Support prioritaire avec réponses accélérées."
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
                    Text("Upgrade plan")
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
                            RevolutStylePlanCard(plan: current, featureRows: featuresFor(plan: current.name))
                                .environmentObject(themeManager)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 460) // homogénéise la hauteur
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
                                    .background(RoundedRectangle(cornerRadius: 28).fill(Color.white))
                                    .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }

                        // Support (comme avant, dans la page)
                        VStack(spacing: 8) {
                            Text("Des questions ?")
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.secondaryTextColor)
                            Link("Contacter le support",
                                 destination: URL(string: "mailto:support@arbore.app") ?? URL(fileURLWithPath: ""))
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
        case "Premium": return "Join Premium"
        case "Metal":   return "Join Metal"
        case "Ultra":   return "Join Ultra"
        default:        return "Join"
        }
    }

    // MARK: - Dynamic background
    @ViewBuilder
    private func backgroundForSelectedPlan(_ plan: String) -> some View {
        switch plan {
        case "Premium":
            LinearGradient(colors: [Color(red: 0.06, green: 0.10, blue: 0.09),
                                    Color(red: 0.03, green: 0.20, blue: 0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case "Metal":
            LinearGradient(colors: [Color(red: 0.08, green: 0.09, blue: 0.10),
                                    Color(red: 0.16, green: 0.18, blue: 0.20)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case "Ultra":
            LinearGradient(colors: [Color(red: 0.08, green: 0.06, blue: 0.12),
                                    Color(red: 0.14, green: 0.10, blue: 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            themeManager.backgroundColor
        }
    }

    // MARK: - Features avec icônes adaptées par plan (style Revolut)
    private func featuresFor(plan name: String) -> [(String, String)] {
        switch name {
        case "Premium":
            return [
                ("camera.viewfinder", "Scans de plantes illimités"),
                ("square.grid.2x2", "Projets multiples (jardin, terrasse, intérieur)"),
                ("sun.max.and.horizon", "Placement intelligent selon l’ensoleillement"),
                ("paintbrush.pointed.fill", "Styles d’aménagement exclusifs"),
                ("bell.badge.fill", "Notifications météo & saison personnalisées"),
                ("icloud.fill", "Synchronisation cloud sécurisée")
            ]
        case "Metal":
            return [
                ("cube.fill", "Plans 3D détaillés avec calques"),
                ("leaf.fill", "Conseils d’entretien avancés par espèce"),
                ("clock.arrow.circlepath", "Historique & suivi des interventions"),
                ("book.closed.fill", "Bibliothèque premium d’espèces et styles"),
                ("bolt.fill", "Analyses et traitements prioritaires")
            ]
        case "Ultra":
            return [
                ("map.fill", "Guides d’aménagement étape par étape"),
                ("cloud.sun.rain.fill", "Assistant météo proactif"),
                ("square.and.arrow.up.on.square.fill", "Exports HD : visuels & listes"),
                ("person.2.fill", "Mode collaboration (lecture)"),
                ("headphones", "Support prioritaire")
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
                    Text(opt)
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
                        .shadow(color: selected == opt ? Color.black.opacity(0.12) : .clear,
                                radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Carte style Revolut (flou + icônes dédiées)
struct RevolutStylePlanCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let plan: PlanModel
    let featureRows: [(icon: String, text: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.name)
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
    let name: String
    let price: String
    let emoji: String
    let description: String
    let features: [String]
    let isPopular: Bool
}

#Preview {
    UpgradePlanView()
        .environmentObject(ThemeManager())
}
