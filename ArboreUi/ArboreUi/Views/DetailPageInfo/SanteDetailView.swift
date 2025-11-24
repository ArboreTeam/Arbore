import SwiftUI

struct SanteDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    /// Infos "Santé" de la plante courante (vient du JSON de ta DB)
    let health: HealthInfo?

    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    headerHero

                    if let health = health {
                        if hasProblemInfo(health: health) {
                            problemsSection(health: health)
                        }

                        if hasPestInfo(health: health) {
                            pestsSection(health: health)
                        }

                        if hasPreventionInfo(health: health) {
                            preventionSection(health: health)
                        }

                        outilsUtilesSection
                        scanSanteCTA
                    } else {
                        HealthSectionCard(
                            icon: "cross.case.fill",
                            iconColor: Color(hex: "#F97316"),
                            title: "Informations indisponibles"
                        ) {
                            Text("Aucune information spécifique sur la santé de cette plante n’est disponible.")
                                .font(.system(size: 14))
                                .foregroundColor(secondaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        outilsUtilesSection
                        scanSanteCTA
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Santé")
    }

    // MARK: - Helpers couleurs

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)
    }

    // MARK: - Sous-titre du header (calculé hors ViewBuilder)

    private var headerSubtitle: String {
        if let firstProblem = health?.commonProblems?.first,
           !firstProblem.isEmpty {
            return firstProblem
        }
        if let firstPest = health?.pests?.first,
           !firstPest.isEmpty {
            return firstPest
        }
        return "Problèmes, parasites, prévention"
    }

    // MARK: - HEADER

    private var headerHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#7F1D1D"), // rouge sombre
                            Color(hex: "#450A0A")  // bordeaux foncé
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
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 30))
                            .foregroundColor(Color(hex: "#F97316"))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Santé")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        Text(headerSubtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }

                    Spacer()
                }

                if let health = health,
                   hasProblemInfo(health: health) || hasPestInfo(health: health) {

                    Divider()
                        .background(Color.white.opacity(0.15))

                    HStack(spacing: 10) {
                        if let count = health.commonProblems?.count, count > 0 {
                            HealthHeaderPill(
                                icon: "exclamationmark.triangle.fill",
                                text: "\(count) problème(s) fréquent(s)"
                            )
                        }
                        if let count = health.pests?.count, count > 0 {
                            HealthHeaderPill(
                                icon: "ant.fill",
                                text: "\(count) parasite(s)"
                            )
                        }
                    }
                } else {
                    Text("Repère rapidement les problèmes les plus courants, les parasites et les gestes de prévention.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section 1 : Problèmes fréquents

    private func hasProblemInfo(health: HealthInfo) -> Bool {
        if let p = health.commonProblems, !p.isEmpty { return true }
        if let s = health.symptomsAndCauses, !s.isEmpty { return true }
        return false
    }

    private func problemsSection(health: HealthInfo) -> some View {
        HealthSectionCard(
            icon: "exclamationmark.triangle.fill",
            iconColor: Color(hex: "#F97316"),
            title: "Problèmes fréquents"
        ) {
            VStack(alignment: .leading, spacing: 12) {

                if let problems = health.commonProblems, !problems.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Problèmes courants")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(primaryTextColor)

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(problems, id: \.self) { problem in
                                HealthBulletRow(text: problem)
                            }
                        }
                    }
                }

                if let symptoms = health.symptomsAndCauses, !symptoms.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Symptômes & causes")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(primaryTextColor)

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(symptoms, id: \.self) { item in
                                HealthBulletRow(text: item)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    // MARK: - Section 2 : Parasites & ravageurs

    private func hasPestInfo(health: HealthInfo) -> Bool {
        if let p = health.pests, !p.isEmpty { return true }
        if let t = health.treatments, !t.isEmpty { return true }
        return false
    }

    private func pestsSection(health: HealthInfo) -> some View {
        HealthSectionCard(
            icon: "ant.fill",
            iconColor: Color(hex: "#22C55E"),
            title: "Parasites & ravageurs"
        ) {
            VStack(alignment: .leading, spacing: 12) {

                if let pests = health.pests, !pests.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Parasites fréquents")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(primaryTextColor)

                        WrapTagCloud(items: pests)
                    }
                }

                if let treatments = health.treatments, !treatments.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Traitements possibles")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(primaryTextColor)

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(treatments, id: \.self) { t in
                                HealthBulletRow(text: t)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Section 3 : Prévention

    private func hasPreventionInfo(health: HealthInfo) -> Bool {
        if let p = health.prevention, !p.isEmpty { return true }
        return false
    }

    private func preventionSection(health: HealthInfo) -> some View {
        HealthSectionCard(
            icon: "shield.lefthalf.filled",
            iconColor: Color(hex: "#22C55E"),
            title: "Prévention"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let prevention = health.prevention, !prevention.isEmpty {
                    ForEach(prevention, id: \.self) { tip in
                        HealthBulletRow(text: tip)
                    }
                }
            }
        }
    }

    // MARK: - Outils utiles (fixe, pas DB)

    private var outilsUtilesSection: some View {
        HealthSectionCard(
            icon: "wrench.and.screwdriver.fill",
            iconColor: Color(hex: "#38BDF8"),
            title: "Outils utiles"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HealthToolRow(
                    systemIcon: "magnifyingglass",
                    title: "Loupe ou zoom photo",
                    subtitle: "Pratique pour inspecter les feuilles et repérer les parasites tôt."
                )
                HealthToolRow(
                    systemIcon: "camera.viewfinder",
                    title: "Photos régulières",
                    subtitle: "Comparer l’état de la plante au fil du temps pour détecter les changements."
                )
            }
        }
    }

    // MARK: - CTA : Scan de santé

    private var scanSanteCTA: some View {
        Button(action: {
            // TODO: lancer plus tard un scan de santé (analyse via caméra / IA)
        }) {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                Text("Lancer un scan de la plante")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.black)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "#BBF7D0"),
                        Color(hex: "#4ADE80")
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

private struct HealthSectionCard<Content: View>: View {
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

private struct HealthBulletRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundColor(Color(hex: "#F97316"))
                .padding(.top, 5)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private struct HealthToolRow: View {
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

// Pastille pour le header
private struct HealthHeaderPill: View {
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

// Tag cloud simple avec LazyVGrid
private struct WrapTagCloud: View {
    @Environment(\.colorScheme) private var colorScheme
    let items: [String]

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 90), spacing: 8, alignment: .leading)
            ],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.04))
                    )
            }
        }
    }
}
