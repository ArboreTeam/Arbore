import SwiftUI

struct TerreDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    /// Infos "Terre & Pot" de la plante courante
    let soil: SoilAndPotInfo?

    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    headerHero

                    if let soil = soil {
                        if hasSubstrateInfo(soil: soil) {
                            substrateSection(soil: soil)
                        }

                        if hasPotInfo(soil: soil) {
                            potSection(soil: soil)
                        }

                        if hasRepotInfo(soil: soil) {
                            repotSection(soil: soil)
                        }

                        outilsUtilesSection
                        mesurerPotCTA
                    } else {
                        SoilSectionCard(
                            icon: "leaf.fill",
                            iconColor: Color(hex: "#4ADE80"),
                            title: NSLocalizedString("SOILDETAIL_INFO_UNAVAILABLE_TITLE", comment: "")
                        ) {
                            Text(NSLocalizedString("SOILDETAIL_INFO_UNAVAILABLE_BODY", comment: ""))
                                .font(.system(size: 14))
                                .foregroundColor(secondaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        outilsUtilesSection
                        mesurerPotCTA
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(NSLocalizedString("SOILDETAIL_NAV_TITLE", comment: ""))
    }

    // MARK: - Helpers couleurs

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)
    }

    private var cardBackgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.11, green: 0.11, blue: 0.12)
        : Color(red: 0.95, green: 0.95, blue: 0.96)
    }

    // MARK: - HEADER

    private var headerHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#431407"),
                            Color(hex: "#1C1917")
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
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Color(hex: "#FACC15"))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("SOILDETAIL_HEADER_TITLE", comment: ""))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        let subtitle = soil?.substrate ?? NSLocalizedString("SOILDETAIL_HEADER_DEFAULT_SUBTITLE", comment: "")
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }

                    Spacer()
                }

                if let soil = soil {
                    Divider()
                        .background(Color.white.opacity(0.15))

                    HStack(spacing: 10) {
                        if let potSize = soil.potSize, !potSize.isEmpty {
                            HeaderMeta(icon: "tray.fill", text: potSize)
                        }
                        if let freq = soil.repotFrequency, !freq.isEmpty {
                            HeaderMeta(icon: "arrow.triangle.2.circlepath", text: freq)
                        }
                    }

                    if let drainage = soil.drainage, !drainage.isEmpty {
                        Text(drainage)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(NSLocalizedString("SOILDETAIL_HEADER_FALLBACK_TEXT", comment: ""))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section 1 : Substrat

    private func hasSubstrateInfo(soil: SoilAndPotInfo) -> Bool {
        if let s = soil.substrate, !s.isEmpty { return true }
        return false
    }

    private func substrateSection(soil: SoilAndPotInfo) -> some View {
        SoilSectionCard(
            icon: "leaf.fill",
            iconColor: Color(hex: "#4ADE80"),
            title: NSLocalizedString("SOILDETAIL_SECTION_SUBSTRATE_TITLE", comment: "")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let substrate = soil.substrate, !substrate.isEmpty {
                    SoilFieldRow(
                        label: NSLocalizedString("SOILDETAIL_FIELD_SOILTYPE", comment: ""),
                        value: substrate
                    )
                }

                if let drainage = soil.drainage, !drainage.isEmpty {
                    SoilFieldRow(
                        label: NSLocalizedString("SOILDETAIL_FIELD_DRAINAGE_RECOMMENDED", comment: ""),
                        value: drainage
                    )
                }
            }
        }
    }

    // MARK: - Section 2 : Pot & drainage

    private func hasPotInfo(soil: SoilAndPotInfo) -> Bool {
        if let p = soil.potSize, !p.isEmpty { return true }
        if let d = soil.drainage, !d.isEmpty { return true }
        return false
    }

    private func potSection(soil: SoilAndPotInfo) -> some View {
        SoilSectionCard(
            icon: "tray.fill",
            iconColor: Color(hex: "#22C55E"),
            title: NSLocalizedString("SOILDETAIL_SECTION_POT_TITLE", comment: "")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let potSize = soil.potSize, !potSize.isEmpty {
                    SoilFieldRow(
                        label: NSLocalizedString("SOILDETAIL_FIELD_POTSIZE", comment: ""),
                        value: potSize
                    )
                }

                if let drainage = soil.drainage, !drainage.isEmpty {
                    SoilFieldRow(
                        label: NSLocalizedString("SOILDETAIL_FIELD_DRAINAGE_ADVICE", comment: ""),
                        value: drainage
                    )
                }
            }
        }
    }

    // MARK: - Section 3 : Rempotage

    private func hasRepotInfo(soil: SoilAndPotInfo) -> Bool {
        if let f = soil.repotFrequency, !f.isEmpty { return true }
        if let s = soil.repotSigns, !s.isEmpty { return true }
        return false
    }

    private func repotSection(soil: SoilAndPotInfo) -> some View {
        SoilSectionCard(
            icon: "arrow.triangle.2.circlepath",
            iconColor: Color(hex: "#EAB308"),
            title: NSLocalizedString("SOILDETAIL_SECTION_REPOT_TITLE", comment: "")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let freq = soil.repotFrequency, !freq.isEmpty {
                    SoilFieldRow(
                        label: NSLocalizedString("SOILDETAIL_FIELD_REPOT_FREQUENCY", comment: ""),
                        value: freq
                    )
                }

                if let signs = soil.repotSigns, !signs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("SOILDETAIL_REPOT_SIGNS_TITLE", comment: ""))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(primaryTextColor)

                        Text(signs)
                            .font(.system(size: 13))
                            .foregroundColor(secondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Outils utiles (génériques)

    private var outilsUtilesSection: some View {
        SoilSectionCard(
            icon: "wrench.and.screwdriver.fill",
            iconColor: Color(hex: "#38BDF8"),
            title: NSLocalizedString("SOILDETAIL_TOOLS_TITLE", comment: "")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SoilToolRow(
                    systemIcon: "scissors",
                    title: NSLocalizedString("SOILDETAIL_TOOLS_PRUNER_TITLE", comment: ""),
                    subtitle: NSLocalizedString("SOILDETAIL_TOOLS_PRUNER_SUBTITLE", comment: "")
                )
                SoilToolRow(
                    systemIcon: "cube.transparent",
                    title: NSLocalizedString("SOILDETAIL_TOOLS_CLAYBALLS_TITLE", comment: ""),
                    subtitle: NSLocalizedString("SOILDETAIL_TOOLS_CLAYBALLS_SUBTITLE", comment: "")
                )
            }
        }
    }

    // MARK: - CTA Mesurer le pot

    private var mesurerPotCTA: some View {
        Button(action: {
            // TODO: plus tard : lancer un outil de mesure AR ou un guide
        }) {
            HStack(spacing: 8) {
                Image(systemName: "ruler.fill")
                Text(NSLocalizedString("SOILDETAIL_CTA_MEASURE_POT", comment: ""))
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.black)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "#FED7AA"),
                        Color(hex: "#FDBA74")
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

// MARK: - Subviews spécifiques Terre & pot

private struct SoilSectionCard<Content: View>: View {
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

private struct SoilFieldRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Text(value)
                .font(.system(size: 14))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SoilToolRow: View {
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

// Pastille réutilisée (copiée depuis Soleil/Eau pour cohérence)
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
