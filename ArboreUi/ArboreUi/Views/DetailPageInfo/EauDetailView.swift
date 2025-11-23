import SwiftUI

struct EauDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    
                    // MARK: - Hero Header
                    headerHero
                    
                    // MARK: - Section Fréquence & Quantité
                    SectionCard(
                        icon: "drop.fill",
                        iconColor: Color(hex: "#60A5FA"),
                        title: "Arrosage"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            HighlightChip(text: "1 fois par semaine")
                            HighlightChip(text: "Environ 200 mL")
                            
                            Text("Un arrosage modéré et régulier favorise une croissance saine. Laisse sécher légèrement la terre entre deux arrosages pour éviter les excès d’humidité.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondaryText(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    // MARK: - Section périodes sensibles
                    SectionCard(
                        icon: "calendar",
                        iconColor: Color(hex: "#FACC15"),
                        title: "Périodes importantes"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(
                                title: "Période critique",
                                subtitle: "Printemps – Été : croissance active.",
                                badge: "Important"
                            )
                            
                            InfoRow(
                                title: "Repos végétatif",
                                subtitle: "Automne – Hiver : réduire l’arrosage.",
                                badge: "Repos"
                            )
                        }
                    }
                    
                    // MARK: - Section à éviter
                    SectionCard(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: Color(hex: "#F97316"),
                        title: "À éviter absolument"
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            WarningRow(
                                icon: "drop.triangle.fill",
                                text: "Eau stagnante au fond du pot : risque élevé de pourriture des racines."
                            )
                            WarningRow(
                                icon: "tortoise.fill",
                                text: "Arrosages trop espacés : flétrissement du feuillage."
                            )
                        }
                    }
                    
                    // MARK: - Section outils utiles
                    SectionCard(
                        icon: "wrench.and.screwdriver.fill",
                        iconColor: Color(hex: "#38BDF8"),
                        title: "Outils utiles"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            ToolRow(
                                systemIcon: "drop.triangle.fill",
                                title: "Moisture Meter",
                                subtitle: "Mesure l’humidité exacte du sol."
                            )
                            ToolRow(
                                systemIcon: "ruler.fill",
                                title: "Water Calculator",
                                subtitle: "Estime la quantité d’eau idéale selon la plante."
                            )
                        }
                    }
                    
                    Spacer().frame(height: 20)
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
            }
        }
        .navigationTitle("Eau")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Hero Header
private var headerHero: some View {
    ZStack {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "#0F172A"), // bleu profond
                        Color(hex: "#075985")  // bleu plus lumineux
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
                    Text("Eau")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text("Fréquence & quantité")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
            }
            
            Divider()
                .background(Color.white.opacity(0.15))
            
            HStack(spacing: 12) {
                PillInfo(icon: "drop.fill", text: "1 fois / semaine")
                PillInfo(icon: "cup.and.saucer.fill", text: "≈ 200 mL")
            }
            
            Text("Apprends à arroser ta plante sans stress : ni trop, ni pas assez, pour garder les racines en bonne santé.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
    }
    .frame(maxWidth: .infinity)
}


// MARK: - Sub-components

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
            HStack {
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

// MARK: - Helpers

private extension Color {
    static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }
    
    static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7)
    }
    
    static func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12)
                        : Color(red: 0.95, green: 0.95, blue: 0.96)
    }
    
    static func accentColor(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#4ADE80") : Color(hex: "#15803D")
    }
}
