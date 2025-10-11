// ✅ LanguageView.swift — version corrigée avec AppStorage et Locale
import SwiftUI

struct LanguageView: View {
    @AppStorage("selectedLanguage") private var selectedLanguage = "en"

    let languages: [String: String] = [
        "en": "English",
        "fr": "Français",
        "es": "Español",
        "de": "Deutsch",
    ]

    var body: some View {
        ZStack {
            Color(hex: "#1A1A1A")
                .ignoresSafeArea()
            
            VStack(alignment: .leading) {
                Text(LocalizedStringKey("language_title"))
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .padding(.horizontal)

                List {
                    ForEach(languages.keys.sorted(), id: \.self) { code in
                        HStack {
                            Text(languages[code] ?? code)
                                .foregroundColor(.white)
                            Spacer()
                            if code == selectedLanguage {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(hex: "#263826"))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedLanguage = code
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text(languages[code] ?? code))
                        .accessibilityAddTraits(code == selectedLanguage ? .isSelected : [])
                        .listRowBackground(Color(hex: "#2A2A2A"))
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color(hex: "#1A1A1A"))
            }
        }
    }
}
