import SwiftUI

struct EntretienView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    /// Infos "care" de la plante courante (hebdo, mensuel, annuel, tips)
    let care: CareInfo?

    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    headerHero

                    if let care = care, hasAnyCareInfo(care) {
                        if let weekly = care.weekly, !weekly.isEmpty {
                            routineSection(
                                icon: "clock.badge.checkmark",
                                iconColor: Color(hex: "#22C55E"),
                                title: "Routines hebdomadaires",
                                tips: weekly
                            )
                        }

                        if let monthly = care.monthly, !monthly.isEmpty {
                            routineSection(
                                icon: "calendar",
                                iconColor: Color(hex: "#FACC15"),
                                title: "Routines mensuelles",
                                tips: monthly
                            )
                        }

                        if let yearly = care.yearly, !yearly.isEmpty {
                            routineSection(
                                icon: "calendar.badge.exclamationmark",
                                iconColor: Color(hex: "#FB923C"),
                                title: "Routines annuelles",
                                tips: yearly
                            )
                        }

                        if let extra = care.extraTips, !extra.isEmpty {
                            routineSection(
                                icon: "lightbulb.fill",
                                iconColor: Color(hex: "#38BDF8"),
                                title: "Astuces supplémentaires",
                                tips: extra
                            )
                        }

                        creerChecklistCTA
                    } else {
                        // Aucune donnée -> message par défaut
                        CareSectionCard(
                            icon: "brain.head.profile",
                            iconColor: Color(hex: "#6366F1"),
                            title: "Aucune routine disponible"
                        ) {
                            Text("Aucune information d’entretien spécifique n’est disponible pour cette plante pour le moment.")
                                .font(.system(size: 14))
                                .foregroundColor(secondaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        creerChecklistCTA
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("🧠 Entretien")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers couleurs

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)
    }

    // Sous-titre dynamique du header
    private var subtitleText: String {
        if let care = care, hasAnyCareInfo(care) {
            return "Routines & bonnes pratiques"
        } else {
            return "Conseils généraux"
        }
    }

    // MARK: - HEADER

    private var headerHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#1E293B"),
                            Color(hex: "#111827")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 10)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 64, height: 64)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 32))
                            .foregroundColor(Color(hex: "#A855F7"))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Entretien")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        Text(subtitleText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }

                    Spacer()
                }

                Text("Planifie l’entretien de ta plante sans prise de tête : routines hebdos, mensuelles, annuelles et astuces pratiques.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Routines (sections dynamiques)

    private func hasAnyCareInfo(_ care: CareInfo) -> Bool {
        if let w = care.weekly, !w.isEmpty { return true }
        if let m = care.monthly, !m.isEmpty { return true }
        if let y = care.yearly, !y.isEmpty { return true }
        if let e = care.extraTips, !e.isEmpty { return true }
        return false
    }

    private func routineSection(
        icon: String,
        iconColor: Color,
        title: String,
        tips: [String]
    ) -> some View {
        CareSectionCard(
            icon: icon,
            iconColor: iconColor,
            title: title
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(tips, id: \.self) { tip in
                    CareChecklistRow(text: tip)
                }
            }
        }
    }

    // MARK: - CTA

    private var creerChecklistCTA: some View {
        Button(action: {
            // TODO: future feature : checklist d’entretien personnalisée
        }) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                Text("Créer ma checklist d’entretien")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.black)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "#E9D5FF"),
                        Color(hex: "#C4B5FD")
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(22)
            .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Subviews spécifiques Entretien

private struct CareSectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let iconColor: Color
    let title: String
    let content: Content

    init(icon: String, iconColor: Color, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.content = content()
    }

    private var cardBackgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.11, green: 0.11, blue: 0.12)
        : Color(red: 0.95, green: 0.95, blue: 0.96)
    }

    private var titleColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(titleColor)

                Spacer()
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

private struct CareChecklistRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "#22C55E"))
                .padding(.top, 2)

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
