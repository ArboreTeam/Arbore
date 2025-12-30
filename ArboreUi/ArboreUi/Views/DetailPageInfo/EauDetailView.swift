import SwiftUI

struct EauDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    /// Infos "Eau" de la plante courante
    let water: WaterInfo?
    let plantName: String
    
    @State private var showingRoutineCreation = false

    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    headerHero

                    if let water = water {
                        arrosageSection(water: water)

                        if hasHumidityInfo(water: water) {
                            humiditySection(water: water)
                        }

                        if hasSignsInfo(water: water) {
                            signsSection(water: water)
                        }

                        outilsUtilesSection
                        testerEauCTA
                    } else {
                        // Aucune donnée → message neutre + outils génériques
                        WaterSectionCard(
                            icon: "drop.fill",
                            iconColor: Color(hex: "#38BDF8"),
                            title: NSLocalizedString("WATERDETAIL_INFO_UNAVAILABLE_TITLE", comment: "")
                        ) {
                            Text(NSLocalizedString("WATERDETAIL_INFO_UNAVAILABLE_BODY", comment: ""))
                                .font(.system(size: 14))
                                .foregroundColor(secondaryTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        outilsUtilesSection
                        testerEauCTA
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(NSLocalizedString("WATERDETAIL_NAV_TITLE", comment: ""))
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
                            Color(hex: "#1F2937"),
                            Color(hex: "#0F172A")
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
                        Image(systemName: "drop.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Color(hex: "#38BDF8"))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("WATERDETAIL_HEADER_TITLE", comment: ""))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        let subtitle = water?.frequency ?? NSLocalizedString("WATERDETAIL_HEADER_DEFAULT_SUBTITLE", comment: "")
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }

                    Spacer()
                }

                if let water = water {
                    Divider()
                        .background(Color.white.opacity(0.15))

                    HStack(spacing: 10) {
                        if let method = water.method, !method.isEmpty {
                            HeaderMeta(icon: "wateringcan", text: method)
                        }
                        if let amount = water.amount, !amount.isEmpty {
                            HeaderMeta(icon: "drop.triangle", text: amount)
                        }
                    }

                    if let recommended = water.recommendedWater, !recommended.isEmpty {
                        let format = NSLocalizedString("WATERDETAIL_HEADER_RECOMMENDED_WATER_FORMAT", comment: "")
                        Text(String(format: format, recommended))
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(NSLocalizedString("WATERDETAIL_HEADER_FALLBACK_TEXT", comment: ""))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section 1 : Arrosage

    private func arrosageSection(water: WaterInfo) -> some View {
        WaterSectionCard(
            icon: "drop.fill",
            iconColor: Color(hex: "#38BDF8"),
            title: NSLocalizedString("WATERDETAIL_WATERING_SECTION_TITLE", comment: "")
        ) {
            VStack(alignment: .leading, spacing: 12) {

                if let freq = water.frequency, !freq.isEmpty {
                    WaterFieldRow(
                        label: NSLocalizedString("WATERDETAIL_FIELD_FREQUENCY", comment: ""),
                        value: freq
                    )
                }

                if let amount = water.amount, !amount.isEmpty {
                    WaterFieldRow(
                        label: NSLocalizedString("WATERDETAIL_FIELD_AMOUNT", comment: ""),
                        value: amount
                    )
                }

                if let method = water.method, !method.isEmpty {
                    WaterFieldRow(
                        label: NSLocalizedString("WATERDETAIL_FIELD_METHOD", comment: ""),
                        value: method
                    )
                }

                if let type = water.recommendedWater, !type.isEmpty {
                    WaterFieldRow(
                        label: NSLocalizedString("WATERDETAIL_FIELD_WATERTYPE", comment: ""),
                        value: type
                    )
                }

                let text = buildWaterDescription(water: water)
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

    private func buildWaterDescription(water: WaterInfo) -> String {
        var parts: [String] = []

        if let freq = water.frequency, !freq.isEmpty {
            let format = NSLocalizedString("WATERDETAIL_WATER_DESC_FREQ_FORMAT", comment: "")
            parts.append(String(format: format, freq.lowercased()))
        }
        if let method = water.method, !method.isEmpty {
            let format = NSLocalizedString("WATERDETAIL_WATER_DESC_METHOD_FORMAT", comment: "")
            parts.append(String(format: format, method.lowercased()))
        }
        if let amount = water.amount, !amount.isEmpty {
            let format = NSLocalizedString("WATERDETAIL_WATER_DESC_AMOUNT_FORMAT", comment: "")
            parts.append(String(format: format, amount.lowercased()))
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Section 2 : Humidité & environnement

    private func hasHumidityInfo(water: WaterInfo) -> Bool {
        if let h = water.humidity, !h.isEmpty { return true }
        if let recommended = water.recommendedWater, !recommended.isEmpty { return true }
        return false
    }

    private func humiditySection(water: WaterInfo) -> some View {
        WaterSectionCard(
            icon: "humidity.fill",
            iconColor: Color(hex: "#22C55E"),
            title: NSLocalizedString("WATERDETAIL_HUMIDITY_SECTION_TITLE", comment: "")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let humidity = water.humidity, !humidity.isEmpty {
                    WaterFieldRow(
                        label: NSLocalizedString("WATERDETAIL_FIELD_IDEAL_HUMIDITY", comment: ""),
                        value: humidity
                    )
                }

                if let recommended = water.recommendedWater, !recommended.isEmpty {
                    let format = NSLocalizedString("WATERDETAIL_HUMIDITY_RECOMMENDED_WATER_FORMAT", comment: "")
                    Text(String(format: format, recommended))
                        .font(.system(size: 13))
                        .foregroundColor(secondaryTextColor)
                }
            }
        }
    }

    // MARK: - Section 3 : Signes à surveiller

    private func hasSignsInfo(water: WaterInfo) -> Bool {
        if let lack = water.signsLack, !lack.isEmpty { return true }
        if let excess = water.signsExcess, !excess.isEmpty { return true }
        return false
    }

    private func signsSection(water: WaterInfo) -> some View {
        WaterSectionCard(
            icon: "exclamationmark.triangle.fill",
            iconColor: Color(hex: "#F97316"),
            title: NSLocalizedString("WATERDETAIL_SIGNS_SECTION_TITLE", comment: "")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let lack = water.signsLack, !lack.isEmpty {
                    WarningBlock(
                        title: NSLocalizedString("WATERDETAIL_SIGNS_LACK_TITLE", comment: ""),
                        icon: "drop.triangle",
                        iconColor: Color(hex: "#FACC15"),
                        text: lack
                    )
                }

                if let excess = water.signsExcess, !excess.isEmpty {
                    WarningBlock(
                        title: NSLocalizedString("WATERDETAIL_SIGNS_EXCESS_TITLE", comment: ""),
                        icon: "drop.triangle.fill",
                        iconColor: Color(hex: "#FB923C"),
                        text: excess
                    )
                }
            }
        }
    }

    // MARK: - Outils utiles

    private var outilsUtilesSection: some View {
        WaterSectionCard(
            icon: "wrench.and.screwdriver.fill",
            iconColor: Color(hex: "#38BDF8"),
            title: NSLocalizedString("WATERDETAIL_TOOLS_TITLE", comment: "")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                WaterToolRow(
                    systemIcon: "drop.fill",
                    title: NSLocalizedString("WATERDETAIL_TOOLS_WATERINGCAN_TITLE", comment: ""),
                    subtitle: NSLocalizedString("WATERDETAIL_TOOLS_WATERINGCAN_SUBTITLE", comment: "")
                )
                WaterToolRow(
                    systemIcon: "gauge",
                    title: NSLocalizedString("WATERDETAIL_TOOLS_MOISTUREMETER_TITLE", comment: ""),
                    subtitle: NSLocalizedString("WATERDETAIL_TOOLS_MOISTUREMETER_SUBTITLE", comment: "")
                )
            }
        }
    }

    // MARK: - CTA

    private var testerEauCTA: some View {
        Button(action: {
            showingRoutineCreation = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "drop.circle.fill")
                Text(NSLocalizedString("WATERDETAIL_CTA_CREATE_ROUTINE", comment: ""))
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.black)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "#BFDBFE"),
                        Color(hex: "#7DD3FC")
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(22)
            .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showingRoutineCreation) {
            CreateWateringRoutineView(
                plantName: plantName,
                waterInfo: water
            )
            .environmentObject(themeManager)
        }
    }
}

// MARK: - Subviews spécifiques Eau

private struct WaterSectionCard<Content: View>: View {
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

private struct WaterFieldRow: View {
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

private struct WarningBlock: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let icon: String
    let iconColor: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct WaterToolRow: View {
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
