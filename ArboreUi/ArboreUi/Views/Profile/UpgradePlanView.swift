import SwiftUI

struct UpgradePlanView: View {
    @Environment(\.dismiss) private var dismiss

    private let benefits: [PremiumBenefit] = [
        PremiumBenefit(
            icon: "paintpalette",
            title: "Tous les styles de jardin",
            description: "Explorez des ambiances plus riches pour créer un espace qui vous ressemble."
        ),
        PremiumBenefit(
            icon: "square.grid.2x2",
            title: "Jusqu'à 30 jardins sauvegardés",
            description: "Gardez vos idées, variantes et projets prêts à reprendre à tout moment."
        ),
        PremiumBenefit(
            icon: "sparkles",
            title: "Outils intelligents pour vos plantes",
            description: "Luminosité, pot et santé : prenez de meilleures décisions, plus vite."
        ),
        PremiumBenefit(
            icon: "person.crop.circle.badge.checkmark",
            title: "Recommandations personnalisées",
            description: "Recevez des conseils plus pertinents selon vos plantes et votre espace."
        )
    ]

    private let comparisonRows: [PremiumComparison] = [
        PremiumComparison(feature: "Styles", freemium: "2 styles", premium: "Tous les styles"),
        PremiumComparison(feature: "Jardins sauvegardés", freemium: "2", premium: "Jusqu'à 30"),
        PremiumComparison(feature: "Catalogue de plantes", freemium: "Limité", premium: "Complet"),
        PremiumComparison(feature: "Outils intelligents", freemium: "Non inclus", premium: "Inclus"),
        PremiumComparison(feature: "Recommandations avancées", freemium: "Limitées", premium: "Incluses")
    ]

    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                SettingsTopBar(title: "Premium") {
                    dismiss()
                }

                ScrollView {
                    VStack(spacing: ArboreDesign.Spacing.xxl) {
                        heroSection
                        benefitsSection
                        comparisonSection
                        reassuranceSection
                    }
                    .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
                    .padding(.top, ArboreDesign.Spacing.lg)
                    .padding(.bottom, 120)
                }

                stickyCTA
            }
        }
        .interactiveDismissDisabled()
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xl) {
            HStack(alignment: .center, spacing: ArboreDesign.Spacing.sm) {
                Text("Arbore Premium")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ArboreDesign.Colors.accentGold)
                    .padding(.horizontal, ArboreDesign.Spacing.sm)
                    .frame(height: 32)
                    .background(ArboreDesign.Colors.accentGold.opacity(0.14))
                    .clipShape(Capsule())

                Spacer(minLength: ArboreDesign.Spacing.sm)

                premiumBadge
            }

            VStack(alignment: .leading, spacing: ArboreDesign.Spacing.sm) {
                Text("Créez le jardin parfait")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Débloquez tous les styles, créez plus de jardins et profitez d'outils intelligents pour prendre soin de vos plantes.")
                    .font(ArboreDesign.Typography.body)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .bottom, spacing: ArboreDesign.Spacing.sm) {
                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("4,99 €")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(ArboreDesign.Colors.accentGold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text("/mois")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(ArboreDesign.Colors.textSecondary)
                    }

                    Label("Annulable à tout moment", systemImage: "checkmark.circle")
                        .font(ArboreDesign.Typography.bodySmall)
                        .foregroundColor(ArboreDesign.Colors.textSecondary)
                }

                Spacer(minLength: ArboreDesign.Spacing.md)

                SettingsIconBadge(
                    systemImage: "crown",
                    tint: ArboreDesign.Colors.accentGold,
                    size: 58
                )
            }
        }
        .padding(ArboreDesign.Spacing.xl)
        .background(premiumHeroBackground)
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.small, style: .continuous)
                .fill(ArboreDesign.Colors.accentGold)
                .frame(width: 70, height: 4)
                .padding(.leading, ArboreDesign.Spacing.xl)
        }
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.image, style: .continuous))
        .shadow(color: ArboreDesign.Colors.shadow, radius: 16, x: 0, y: 8)
    }

    private var premiumHeroBackground: some View {
        RoundedRectangle(cornerRadius: ArboreDesign.Radius.image, style: .continuous)
            .fill(ArboreDesign.Colors.elevatedCard)
            .overlay(
                LinearGradient(
                    colors: [
                        ArboreDesign.Colors.accentGold.opacity(0.18),
                        ArboreDesign.Colors.card.opacity(0.0),
                        ArboreDesign.Colors.primaryGreen.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.image, style: .continuous)
                    .stroke(ArboreDesign.Colors.accentGold.opacity(0.28), lineWidth: 1)
            )
    }

    private var premiumBadge: some View {
        HStack(spacing: ArboreDesign.Spacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))

            Text("1er mois gratuit")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(ArboreDesign.Colors.textPrimary)
        .padding(.horizontal, ArboreDesign.Spacing.sm)
        .frame(height: 32)
        .background(ArboreDesign.Colors.card)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(ArboreDesign.Colors.accentGold.opacity(0.45), lineWidth: 1)
        )
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
            sectionHeader(
                eyebrow: "Ce que vous débloquez",
                title: "Plus de liberté, moins d'hésitation"
            )

            AppCard {
                VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
                    ForEach(Array(benefits.enumerated()), id: \.offset) { index, benefit in
                        PremiumBenefitRow(benefit: benefit, isFeatured: index == 0)

                        if index < benefits.count - 1 {
                            SettingsDivider()
                        }
                    }
                }
            }
        }
    }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.md) {
            sectionHeader(
                eyebrow: "Comparaison",
                title: "Premium en un coup d'oeil"
            )

            AppCard {
                VStack(spacing: ArboreDesign.Spacing.md) {
                    HStack(spacing: ArboreDesign.Spacing.sm) {
                        PlanColumnHeader(title: "Freemium", isPremium: false)
                        PlanColumnHeader(title: "Premium", isPremium: true)
                    }

                    VStack(spacing: ArboreDesign.Spacing.sm) {
                        ForEach(Array(comparisonRows.enumerated()), id: \.offset) { index, row in
                            PremiumComparisonRow(row: row)

                            if index < comparisonRows.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var reassuranceSection: some View {
        HStack(alignment: .top, spacing: ArboreDesign.Spacing.sm) {
            SettingsIconBadge(
                systemImage: "checkmark.seal",
                tint: ArboreDesign.Colors.primaryGreen,
                size: 42
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Essayez Premium librement.")
                    .font(ArboreDesign.Typography.cardTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)

                Text("Conçu pour simplifier le jardinage, pas pour le compliquer. Vous pouvez annuler à tout moment.")
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(ArboreDesign.Spacing.md)
        .background(ArboreDesign.Colors.softSurface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                .stroke(ArboreDesign.Colors.border, lineWidth: 1)
        )
    }

    private var stickyCTA: some View {
        VStack(spacing: ArboreDesign.Spacing.sm) {
            Button(action: startPremiumTrial) {
                HStack(spacing: ArboreDesign.Spacing.xs) {
                    Image(systemName: "sparkles")
                    Text("Commencer mon essai gratuit")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .buttonStyle(.arborePrimary)

            Text("Puis 4,99 €/mois · annulable à tout moment")
                .font(ArboreDesign.Typography.caption)
                .foregroundColor(ArboreDesign.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, ArboreDesign.Spacing.screenHorizontal)
        .padding(.top, ArboreDesign.Spacing.md)
        .padding(.bottom, ArboreDesign.Spacing.lg)
        .background(ArboreDesign.Colors.card)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ArboreDesign.Colors.border)
                .frame(height: 1)
        }
    }

    private func sectionHeader(eyebrow: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xxs) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ArboreDesign.Colors.accentGold)

            Text(title)
                .font(ArboreDesign.Typography.sectionTitle)
                .foregroundColor(ArboreDesign.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startPremiumTrial() {
        // Existing placeholder purchase flow: keep the current behavior.
        dismiss()
    }
}

private struct PremiumBenefit {
    let icon: String
    let title: String
    let description: String
}

private struct PremiumComparison {
    let feature: String
    let freemium: String
    let premium: String
}

private struct PremiumBenefitRow: View {
    let benefit: PremiumBenefit
    let isFeatured: Bool

    var body: some View {
        HStack(alignment: .top, spacing: ArboreDesign.Spacing.sm) {
            SettingsIconBadge(
                systemImage: benefit.icon,
                tint: isFeatured ? ArboreDesign.Colors.accentGold : ArboreDesign.Colors.primaryGreen,
                size: 42
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(benefit.title)
                    .font(ArboreDesign.Typography.cardTitle)
                    .foregroundColor(ArboreDesign.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(benefit.description)
                    .font(ArboreDesign.Typography.bodySmall)
                    .foregroundColor(ArboreDesign.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct PlanColumnHeader: View {
    let title: String
    let isPremium: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(isPremium ? ArboreDesign.Colors.textPrimary : ArboreDesign.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(isPremium ? ArboreDesign.Colors.accentGold.opacity(0.20) : ArboreDesign.Colors.softSurface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isPremium ? ArboreDesign.Colors.accentGold.opacity(0.45) : ArboreDesign.Colors.border, lineWidth: 1)
            )
    }
}

private struct PremiumComparisonRow: View {
    let row: PremiumComparison

    var body: some View {
        VStack(alignment: .leading, spacing: ArboreDesign.Spacing.xs) {
            Text(row.feature)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ArboreDesign.Colors.textPrimary)

            HStack(alignment: .top, spacing: ArboreDesign.Spacing.sm) {
                ComparisonValue(text: row.freemium, isPremium: false)
                ComparisonValue(text: row.premium, isPremium: true)
            }
        }
        .padding(.vertical, ArboreDesign.Spacing.xs)
    }
}

private struct ComparisonValue: View {
    let text: String
    let isPremium: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isPremium ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isPremium ? ArboreDesign.Colors.primaryGreen : ArboreDesign.Colors.textMuted)
                .padding(.top, 1)

            Text(text)
                .font(ArboreDesign.Typography.caption.weight(isPremium ? .semibold : .regular))
                .foregroundColor(isPremium ? ArboreDesign.Colors.textPrimary : ArboreDesign.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(ArboreDesign.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(isPremium ? ArboreDesign.Colors.accentGold.opacity(0.12) : ArboreDesign.Colors.softSurface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: ArboreDesign.Radius.medium, style: .continuous))
    }
}

#Preview {
    UpgradePlanView()
        .environmentObject(ThemeManager())
}
