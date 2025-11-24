import SwiftUI

struct CycleDeVieView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    /// Infos "Cycle de vie" de la plante courante (vient de ta DB)
    let lifecycle: LifeCycleInfo?

    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    headerHero

                    if let lifecycle = lifecycle {
                        if hasPhaseInfo(lifecycle: lifecycle) {
                            phasesSection(lifecycle: lifecycle)
                        }

                        if hasCareInfo(lifecycle: lifecycle) {
                            careSection(lifecycle: lifecycle)
                        }

                        outilsUtilesSection
                        planifierCycleCTA
                    } else {
                        LifecycleSectionCard(
                            icon: "calendar",
                            iconColor: Color(hex: "#F97316"),
                            title: "Informations indisponibles"
                        ) {
                            Text("Aucune information spécifique sur le cycle de vie de cette plante n’est disponible.")
                                .font(.system(size: 14))
                                .foregroundColor(secondaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        outilsUtilesSection
                        planifierCycleCTA
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Cycle de vie")
    }

    // MARK: - Helpers couleurs

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)
    }

    // MARK: - Sous-titre header (hors ViewBuilder)

    private var headerSubtitle: String {
        if let growth = lifecycle?.growth, !growth.isEmpty {
            return "Croissance : \(growth)"
        }
        if let flowering = lifecycle?.flowering, !flowering.isEmpty {
            return "Floraison : \(flowering)"
        }
        if let dormancy = lifecycle?.dormancy, !dormancy.isEmpty {
            return "Repos : \(dormancy)"
        }
        return "Croissance, floraison, repos"
    }

    // MARK: - HEADER

    private var headerHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#1E293B"), // bleu nuit
                            Color(hex: "#4C1D95")  // violet profond
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
                        Image(systemName: "calendar")
                            .font(.system(size: 30))
                            .foregroundColor(Color(hex: "#FACC15"))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cycle de vie")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        Text(headerSubtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }

                    Spacer()
                }

                if let lifecycle = lifecycle,
                   hasPhaseInfo(lifecycle: lifecycle) {

                    Divider()
                        .background(Color.white.opacity(0.15))

                    HStack(spacing: 10) {
                        if let growth = lifecycle.growth, !growth.isEmpty {
                            LifecycleHeaderPill(icon: "leaf.fill", text: growth)
                        }
                        if let dormancy = lifecycle.dormancy, !dormancy.isEmpty {
                            LifecycleHeaderPill(icon: "moon.zzz.fill", text: dormancy)
                        }
                    }
                } else {
                    Text("Visualise les grandes étapes de l’année pour adapter ton entretien au bon moment.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section 1 : Phases du cycle

    private func hasPhaseInfo(lifecycle: LifeCycleInfo) -> Bool {
        if let g = lifecycle.growth, !g.isEmpty { return true }
        if let f = lifecycle.flowering, !f.isEmpty { return true }
        if let d = lifecycle.dormancy, !d.isEmpty { return true }
        return false
    }

    private func phasesSection(lifecycle: LifeCycleInfo) -> some View {
        LifecycleSectionCard(
            icon: "clock.arrow.circlepath",
            iconColor: Color(hex: "#FACC15"),
            title: "Phases du cycle"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let growth = lifecycle.growth, !growth.isEmpty {
                    LifecycleKeyValueRow(label: "Période de croissance", value: growth)
                }
                if let flowering = lifecycle.flowering, !flowering.isEmpty {
                    LifecycleKeyValueRow(label: "Floraison", value: flowering)
                }
                if let dormancy = lifecycle.dormancy, !dormancy.isEmpty {
                    LifecycleKeyValueRow(label: "Période de repos", value: dormancy)
                }

                let text = buildPhasesDescription(lifecycle: lifecycle)
                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundColor(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func buildPhasesDescription(lifecycle: LifeCycleInfo) -> String {
        var parts: [String] = []

        if let growth = lifecycle.growth, !growth.isEmpty {
            parts.append("La plante se développe surtout pendant \(growth.lowercased()).")
        }
        if let flowering = lifecycle.flowering, !flowering.isEmpty {
            parts.append("La floraison a lieu en général \(flowering.lowercased()).")
        }
        if let dormancy = lifecycle.dormancy, !dormancy.isEmpty {
            parts.append("Prévoyez une période plus calme \(dormancy.lowercased()) pour laisser la plante se reposer.")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Section 2 : Entretien lié au cycle

    private func hasCareInfo(lifecycle: LifeCycleInfo) -> Bool {
        if let f = lifecycle.fertilizer, !f.isEmpty { return true }
        if let p = lifecycle.pruning, !p.isEmpty { return true }
        return false
    }

    private func careSection(lifecycle: LifeCycleInfo) -> some View {
        LifecycleSectionCard(
            icon: "leaf.circle.fill",
            iconColor: Color(hex: "#22C55E"),
            title: "Entretien selon le cycle"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let fertilizer = lifecycle.fertilizer, !fertilizer.isEmpty {
                    LifecycleKeyValueRow(label: "Engrais", value: fertilizer)
                }
                if let pruning = lifecycle.pruning, !pruning.isEmpty {
                    LifecycleKeyValueRow(label: "Taille", value: pruning)
                }
            }
        }
    }

    // MARK: - Outils utiles (UI fixe)

    private var outilsUtilesSection: some View {
        LifecycleSectionCard(
            icon: "wrench.and.screwdriver.fill",
            iconColor: Color(hex: "#38BDF8"),
            title: "Outils utiles"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                LifecycleToolRow(
                    systemIcon: "calendar.badge.clock",
                    title: "Agenda d’entretien",
                    subtitle: "Note les périodes de croissance, de repos et les moments pour fertiliser."
                )
                LifecycleToolRow(
                    systemIcon: "bell.badge",
                    title: "Rappels saisonniers",
                    subtitle: "Crée des rappels avant les périodes clés (croissance, floraison, repos)."
                )
            }
        }
    }

    // MARK: - CTA (UI fixe)

    private var planifierCycleCTA: some View {
        Button(action: {
            // TODO: plus tard : ouvrir une vue de planning / rappels
        }) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.plus")
                Text("Planifier l’année de la plante")
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

// MARK: - Subviews

private struct LifecycleSectionCard<Content: View>: View {
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

private struct LifecycleKeyValueRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
        }
    }
}

private struct LifecycleBulletRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundColor(Color(hex: "#FACC15"))
                .padding(.top, 5)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private struct LifecycleToolRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemIcon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemIcon)
                .font(.system(size: 18))
                .foregroundColor(Color(hex: "#38BDF8"))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct LifecycleHeaderPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
    }
}
