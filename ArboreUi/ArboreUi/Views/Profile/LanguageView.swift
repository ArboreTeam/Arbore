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
        VStack(alignment: .leading) {
            Text(LocalizedStringKey("language_title"))
                .font(.largeTitle)
                .bold()
                .padding(.top, 20)
                .padding(.horizontal)

            List {
                ForEach(languages.keys.sorted(), id: \.self) { code in
                    HStack {
                        Text(languages[code] ?? code)
                        Spacer()
                        if code == selectedLanguage {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedLanguage = code
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(languages[code] ?? code))
                    .accessibilityAddTraits(code == selectedLanguage ? .isSelected : [])
                }
            }
        }
    }
}
