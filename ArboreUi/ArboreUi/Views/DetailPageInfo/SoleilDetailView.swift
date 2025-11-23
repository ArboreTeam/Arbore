import SwiftUI

struct SoleilDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    let plant: Plant
    let selectedLanguage: String
    
    // Raccourci vers les traductions dans la bonne langue (fallback FR)
    private var t: [String: String] {
        plant.translations[selectedLanguage]
        ?? plant.translations["fr"]
        ?? [:]
    }
    
    // MARK: - Contenu Soleil venant de l’IA (avec fallback)
    
    private var overviewHighlight1: String {
        t["soleil_overview_highlight1"]
        ?? "Lumière vive indirecte"
    }
    
    private var overviewHighlight2: String {
        t["soleil_overview_highlight2"]
        ?? "Éviter le plein soleil brûlant"
    }
    
    private var overviewText: String {
        t["soleil_overview"]
        ?? "La plupart des plantes d’intérieur apprécient une lumière vive mais filtrée. Trop de soleil direct peut brûler le feuillage, tandis qu’un manque de lumière ralentit la croissance."
    }
    
    private var windowsText: String {
        t["soleil_windows"]
        ?? "Est ou Ouest, à 1–3 mètres de la fenêtre."
    }
    
    private var roomsText: String {
        t["soleil_rooms"]
        ?? "Salon lumineux, bureau, chambre bien éclairée."
    }
    
    private var tagList: [String] {
        if let tagsString = t["soleil_tags"] {
            let parts = tagsString
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return parts }
        }
        // Fallback si pas de tags IA
        return ["Fenêtre Est", "Fenêtre Ouest", "Lumière filtrée", "Voilage fin"]
    }
    
    private var watch1: String {
        t["soleil_watch1"]
        ?? "Feuilles qui brûlent ou se décolorent : la plante est trop proche d’une source de soleil direct."
    }
    
    private var watch2: String {
        t["soleil_watch2"]
        ?? "Tiges qui s’allongent et feuilles qui pâlissent : manque de lumière, rapproche la plante d’une fenêtre."
    }
    
    private var watch3: String {
        t["soleil_watch3"]
        ?? "Pense à tourner le pot régulièrement pour éviter que la plante ne penche d’un seul côté."
    }
    
    private var toolLightMeter: String {
        t["soleil_tool_lightmeter"]
        ?? "Mesure l’intensité lumineuse à l’endroit exact où tu poses la plante."
    }
    
    private var toolCompass: String {
        t["soleil_tool_compass"]
        ?? "T’aide à identifier l’orientation des fenêtres (Est, Ouest, Sud, Nord)."
    }

    var body: some View {
        ZStack {
            // Fond global : même que les autres pages (gris sombre du thème)
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    
                    // MARK: - Hero Header
                    headerHero
                    
                    // MARK: - Section "Vue d’ensemble"
                    SectionCard(
                        icon: "sun.max.fill",
                        iconColor: Color(hex: "#FACC15"),
                        title: "Vue d’ensemble"
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            HighlightChip(text: overviewHighlight1)
                            HighlightChip(text: overviewHighlight2)
                            
                            Text(overviewText)
                                .font(.system(size: 14))
                                .foregroundColor(.secondaryText(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    // MARK: - Section "Où placer la plante ?"
                    SectionCard(
                        icon: "house.fill",
                        iconColor: Color(hex: "#22C55E"),
                        title: "Où placer la plante ?"
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            InfoRow(
                                title: "Fenêtres idéales",
                                subtitle: windowsText,
                                badge: "Recommandé"
                            )
                            InfoRow(
                                title: "Pièces conseillées",
                                subtitle: roomsText,
                                badge: "Confort"
                            )
                            
                            sunTagCloud(tags: tagList)
                        }
                    }
                    
                    // MARK: - Section "À surveiller"
                    SectionCard(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: Color(hex: "#F97316"),
                        title: "À surveiller"
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            WarningRow(
                                icon: "flame.fill",
                                text: watch1
                            )
                            WarningRow(
                                icon: "arrow.down.right.and.arrow.up.left",
                                text: watch2
                            )
                            WarningRow(
                                icon: "arrow.triangle.2.circlepath",
                                text: watch3
                            )
                        }
                    }
                    
                    // MARK: - Section "Outils utiles"
                    SectionCard(
                        icon: "wrench.and.screwdriver.fill",
                        iconColor: Color(hex: "#38BDF8"),
                        title: "Outils utiles"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            ToolRow(
                                systemIcon: "lightbulb.max.fill",
                                title: "Light meter",
                                subtitle: toolLightMeter
                            )
                            ToolRow(
                                systemIcon: "location.north.line",
                                title: "Boussole",
                                subtitle: toolCompass
                            )
                        }
                    }
                    
                    // MARK: - Call to action
                    Button(action: {
                        // TODO: déclencher un test de lumière ou une feature plus tard
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
                    .padding(.bottom, 32)
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Soleil")
    }
    
    // MARK: - Hero Header
    private var headerHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#064E3B"), // proche du vert de ta navigation
                            Color(hex: "#065F46")
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
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                        Text("Exposition & orientation")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    
                    Spacer()
                }
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                HStack(spacing: 12) {
                    // 🟢 ICI la correction : plant.exposure (camelCase)
                    PillInfo(
                        icon: "sun.max",
                        text: plant.exposure.isEmpty
                            ? "Lumière vive indirecte"
                            : plant.exposure
                    )
                    PillInfo(icon: "clock.arrow.circlepath", text: "8–12 h / jour")
                }
                
                Text(overviewText)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sub-components (inchangés, juste réutilisés)

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

private struct HighlightChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.accentColor(for: colorScheme))
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.04))
            )
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

private struct WarningRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color(hex: "#F97316"))
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14))
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

// Tag cloud sans chevauchement : fonction, pas de struct → pas de problème d’accessibilité
private func sunTagCloud(tags: [String]) -> some View {
    GeometryReader { _ in
        let columns = [
            GridItem(.adaptive(minimum: 110), spacing: 8, alignment: .leading)
        ]
        
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                TagChip(text: tag)
            }
        }
    }
    .frame(minHeight: 0)
}

private struct TagChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondaryText(for: colorScheme))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.03))
            )
    }
}

private struct PillInfo: View {
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
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Helpers (colors)

private extension Color {
    static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }
    
    static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7)
    }
    
    static func cardBackground(for scheme: ColorScheme) -> Color {
        // Gris foncé comme les autres cartes (proche de systemGray6 en dark)
        scheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12)
                        : Color(red: 0.95, green: 0.95, blue: 0.96)
    }
    
    static func accentColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#4ADE80") : Color(hex: "#15803D")
    }
}
