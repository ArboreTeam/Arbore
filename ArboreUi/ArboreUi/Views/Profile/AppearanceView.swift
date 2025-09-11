import SwiftUI

struct AppearanceView: View {
    @AppStorage("selectedColorScheme") private var selectedColorScheme: String = "Default"
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("dynamicTypeSize") private var dynamicTypeSize: Double = 1.0

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
                            if scheme == selectedColorScheme {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedColorScheme = scheme
                            applyColorScheme(scheme)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(scheme), \(colorSchemes[scheme] ?? "")")
                        .accessibilityAddTraits(scheme == selectedColorScheme ? .isSelected : [])
                    }
                }

                Section(header: Text(LocalizedStringKey("display_mode"))) {
                    Toggle(isOn: $isDarkMode) {
                        Text(LocalizedStringKey("dark_mode"))
                    }
                    .onChange(of: isDarkMode) {
                        applyDarkMode()
                    }
                }

                Section(header: Text(LocalizedStringKey("text_size"))) {
                    Slider(value: $dynamicTypeSize, in: 0.8...1.5, step: 0.1) {
                        Text(LocalizedStringKey("text_size"))
                    }
                    .accessibilityValue("\(Int(dynamicTypeSize * 100))%")
                    Text("\(Int(dynamicTypeSize * 100))%")
                        .font(.caption)
                }
            }
        }
    }

    func applyColorScheme(_ scheme: String) {
        UserDefaults.standard.set(scheme, forKey: "ColorScheme")
    }

    func applyDarkMode() {
        UserDefaults.standard.set(isDarkMode, forKey: "isDarkMode")
    }
}
