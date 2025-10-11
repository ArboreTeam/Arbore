import SwiftUI

struct AppearanceView: View {
    @EnvironmentObject var themeManager: ThemeManager

    let colorSchemes: [String: String] = [
        "Default": "Normal",
        "Protanopia": "Rouge-vert",
        "Deuteranopia": "Rouge-vert",
        "Tritanopia": "Bleu-jaune"
    ]

    var body: some View {
        VStack(alignment: .leading) {
            Text(LocalizedStringKey("appearance_title"))
                .font(.largeTitle)
                .bold()
                .padding(.top, 20)
                .padding(.horizontal)

            List {
                Section(header: Text("Mode d'affichage")) {
                    Toggle("Utiliser le thème système", isOn: $themeManager.useSystemTheme)
                    
                    if !themeManager.useSystemTheme {
                        Toggle("Mode sombre", isOn: $themeManager.manualDarkMode)
                    }
                }
                
                Section(header: Text(LocalizedStringKey("color_adjustments"))) {
                    ForEach(colorSchemes.keys.sorted(), id: \.self) { scheme in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(LocalizedStringKey(scheme))
                                    .fontWeight(.bold)
                                Text(colorSchemes[scheme] ?? "")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            if scheme == themeManager.selectedColorScheme {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            themeManager.selectedColorScheme = scheme
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(scheme), \(colorSchemes[scheme] ?? "")")
                        .accessibilityAddTraits(scheme == themeManager.selectedColorScheme ? .isSelected : [])
                    }
                }

                Section(header: Text(LocalizedStringKey("text_size"))) {
                    Slider(value: $themeManager.dynamicTypeSize, in: 0.8...1.5, step: 0.1) {
                        Text(LocalizedStringKey("text_size"))
                    }
                    .accessibilityValue("\(Int(themeManager.dynamicTypeSize * 100))%")
                    Text("\(Int(themeManager.dynamicTypeSize * 100))%")
                        .font(.caption)
                }
            }
        }
        .background(themeManager.backgroundColor)
    }
}
