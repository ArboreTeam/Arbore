import SwiftUI

struct SoleilDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    /// Infos "Soleil" de la plante courante
    let sun: SunInfo?

    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    headerHero

                    if let sun = sun {
                        lightSection(sun: sun)

                        if hasPlacementInfo(sun: sun) {
                            placementSection(sun: sun)
                        }

                        if let tips = sun.tips, !tips.isEmpty {
                            tipsSection(tips: tips)
                        }

                        outilsUtilesSection
                        testerLumiereCTA
                    } else {
                        SectionCard(
                            icon: "sun.max.fill",
                            iconColor: Color(hex: "#FACC15"),
                            title: "Informations indisponibles"
                        ) {
                            Text("Aucune information spécifique sur la lumière n’est disponible pour cette plante.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondaryText(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        outilsUtilesSection
                        testerLumiereCTA
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Soleil")
    }

    // MARK: - HEADER

    private var headerHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#263826"),
                            Color(hex: "#1F2B20")
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
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Color(hex: "#FACC15"))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Soleil")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        let subtitle = sun?.lightType ?? "Lumière & emplacement"
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }

                    Spacer()
                }

                if let sun = sun {
                    Divider()
                        .background(Color.white.opacity(0.15))

                    HStack(spacing: 10) {
                        if let duration = sun.durationPerDay, !duration.isEmpty {
                            HeaderMeta(icon: "clock", text: duration)
                        }
                        if let orientation = sun.orientation, !orientation.isEmpty {
                            HeaderMeta(icon: "location.north.line", text: orientation)
                        }
                    }

                    if let distance = sun.windowDistance, !distance.isEmpty {
                        Text("Idéale à environ \(distance.lowercased()) de la fenêtre.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Comprends rapidement quel type de lumière convient le mieux à cette plante.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section 1 : Lumière quotidienne

    private func lightSection(sun: SunInfo) -> some View {
        SectionCard(
            icon: "sun.max.fill",
            iconColor: Color(hex: "#FACC15"),
            title: "Lumière quotidienne"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let light = sun.lightType, !light.isEmpty {
                    KeyValueRow(label: "Type", value: light)
                }

                if let duration = sun.durationPerDay, !duration.isEmpty {
                    KeyValueRow(label: "Durée idéale", value: duration)
                }

                let text = buildLightDescription(sun: sun)
                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundColor(.secondaryText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func buildLightDescription(sun: SunInfo) -> String {
        var parts: [String] = []

        if let light = sun.lightType, !light.isEmpty {
            parts.append("Cette plante préfère une lumière \(light.lowercased()).")
        }
        if let duration = sun.durationPerDay, !duration.isEmpty {
            parts.append("Essaie de lui offrir environ \(duration.lowercased()) par jour.")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Section 2 : Emplacement idéal

    private func hasPlacementInfo(sun: SunInfo) -> Bool {
        if let o = sun.orientation, !o.isEmpty { return true }
        if let d = sun.windowDistance, !d.isEmpty { return true }
        if let rooms = sun.recommendedRooms, !rooms.isEmpty { return true }
        return false
    }

    private func placementSection(sun: SunInfo) -> some View {
        SectionCard(
            icon: "house.fill",
            iconColor: Color(hex: "#22C55E"),
            title: "Emplacement idéal"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if let orientation = sun.orientation, !orientation.isEmpty {
                    let distance = (sun.windowDistance ?? "").isEmpty ? nil : sun.windowDistance
                    let subtitle = distance.map { "\(orientation) • \($0)" } ?? orientation

                    InfoRow(
                        title: "Fenêtres recommandées",
                        subtitle: subtitle,
                        badge: "Recommandé"
                    )
                }

                if let rooms = sun.recommendedRooms, !rooms.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pièces conseillées")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primaryText(for: colorScheme))

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(rooms, id: \.self) { room in
                                HStack(spacing: 6) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundColor(Color(hex: "#22C55E"))
                                    Text(room)
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondaryText(for: colorScheme))
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    if let orientation = sun.orientation, !orientation.isEmpty {
                        PillTag(text: orientation)
                    }
                    if let distance = sun.windowDistance, !distance.isEmpty {
                        PillTag(text: distance)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Section 3 : Conseils & astuces

    private func tipsSection(tips: [String]) -> some View {
        SectionCard(
            icon: "lightbulb.max.fill",
            iconColor: Color(hex: "#FDE68A"),
            title: "Conseils & astuces"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(tips, id: \.self) { tip in
                    TipRow(text: tip)
                }
            }
        }
    }

    // MARK: - Outils utiles

    private var outilsUtilesSection: some View {
        SectionCard(
            icon: "wrench.and.screwdriver.fill",
            iconColor: Color(hex: "#38BDF8"),
            title: "Outils utiles"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ToolRow(
                    systemIcon: "lightbulb.max.fill",
                    title: "Light meter",
                    subtitle: "Mesure l’intensité lumineuse à l’endroit exact où tu poses la plante."
                )
                ToolRow(
                    systemIcon: "location.north.line",
                    title: "Boussole",
                    subtitle: "T’aide à identifier l’orientation des fenêtres (Est, Ouest, Sud, Nord)."
                )
            }
        }
    }

    // MARK: - CTA

    private var testerLumiereCTA: some View {
        Button(action: {
            // TODO: déclencher un test de lumière plus tard
        }) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.trianglebadge.exclamationmark.fill")
                Text("Tester la lumière de ma pièce")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.black)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "#BBF7D0"),
                        Color(hex: "#6EE7B7")
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

// MARK: - Subviews & Helpers

private struct SectionCard<Content: View>: View {
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
                    .foregroundColor(.primaryText(for: colorScheme))

                Spacer()
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.cardBackground(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

private struct HeaderMeta: View {
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

private struct KeyValueRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primaryText(for: colorScheme))
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(.secondaryText(for: colorScheme))
        }
    }
}

private struct InfoRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    let badge: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primaryText(for: colorScheme))
                Spacer()
                Text(badge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        Capsule()
                            .fill(Color(hex: "#BBF7D0"))
                    )
            }
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(.secondaryText(for: colorScheme))
        }
    }
}

private struct TipRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#FACC15"))
                .padding(.top, 4)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct ToolRow: View {
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
                    .foregroundColor(.primaryText(for: colorScheme))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PillTag: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondaryText(for: colorScheme))
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.04))
            )
    }
}

// MARK: - Color helpers

private extension Color {
    static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }

    static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7)
    }

    static func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark
        ? Color(red: 0.11, green: 0.11, blue: 0.12)
        : Color(red: 0.95, green: 0.95, blue: 0.96)
    }
}
