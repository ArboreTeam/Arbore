import SwiftUI

struct AppearanceView: View {
    @EnvironmentObject var themeManager: ThemeManager

    let colorSchemes: [String: String] = [
        "Default": "Normal",
        "Protanopia": "Rouge-vert",
        "Deuteranopia": "Rouge-vert",
        "Tritanopia": "Bleu-jaune"
    ]
    
    private let demoColors: [Color] = [.red, .green, .blue, .yellow, .purple, .orange]

    var body: some View {
        VStack(alignment: .leading) {
            Text(LocalizedStringKey("appearance_title"))
                .font(.largeTitle)
                .bold()
                .padding(.top, 20)
                .padding(.horizontal)
                .foregroundColor(themeManager.textColor)

            List {
                Section(header: Text("Mode d'affichage").foregroundColor(themeManager.textColor)) {
                    Toggle("Utiliser le thème système", isOn: $themeManager.useSystemTheme)
                        .foregroundColor(themeManager.textColor)
                    
                    if !themeManager.useSystemTheme {
                        Toggle("Mode sombre", isOn: $themeManager.manualDarkMode)
                            .foregroundColor(themeManager.textColor)
                    }
                }
                
                Section(header: Text(LocalizedStringKey("color_adjustments")).foregroundColor(themeManager.textColor)) {
                    ForEach(colorSchemes.keys.sorted(), id: \.self) { scheme in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(LocalizedStringKey(scheme))
                                        .fontWeight(.bold)
                                        .foregroundColor(themeManager.textColor)
                                    Text(colorSchemes[scheme] ?? "")
                                        .font(.caption)
                                        .foregroundColor(themeManager.secondaryTextColor)
                                }
                                Spacer()
                                if scheme == themeManager.selectedColorScheme {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(themeManager.accentColor)
                                        .font(.title2)
                                }
                            }
                            
                            // Aperçu des couleurs avec le filtre appliqué
                            HStack(spacing: 6) {
                                ForEach(demoColors, id: \.self) { baseColor in
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(previewColor(baseColor, scheme: scheme))
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(themeManager.secondaryTextColor.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                themeManager.selectedColorScheme = scheme
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(scheme), \(colorSchemes[scheme] ?? "")")
                        .accessibilityAddTraits(scheme == themeManager.selectedColorScheme ? .isSelected : [])
                    }
                }

                Section(header: Text(LocalizedStringKey("text_size")).foregroundColor(themeManager.textColor)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("A")
                                .font(.caption)
                                .foregroundColor(themeManager.secondaryTextColor)
                            Slider(value: $themeManager.dynamicTypeSize, in: 0.8...1.5, step: 0.1)
                            Text("A")
                                .font(.title2)
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                        
                        HStack {
                            Text("Taille: \(Int(themeManager.dynamicTypeSize * 100))%")
                                .font(.caption)
                                .foregroundColor(themeManager.secondaryTextColor)
                            Spacer()
                            Text("Exemple de texte")
                                .foregroundColor(themeManager.textColor)
                        }
                    }
                    .accessibilityValue("\(Int(themeManager.dynamicTypeSize * 100))%")
                }
            }
        }
        .background(themeManager.backgroundColor)
    }
    
    // Fonction pour prévisualiser une couleur avec un filtre spécifique
    private func previewColor(_ color: Color, scheme: String) -> Color {
        guard scheme != "Default" else { return color }
        let temp = ThemeManager()
        temp.selectedColorScheme = scheme
        return temp.adjust(color)
    }
}
