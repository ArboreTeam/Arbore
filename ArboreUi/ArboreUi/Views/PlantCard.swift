import SwiftUI

struct PlantCard: View {
    let plant: Plant
    @AppStorage("selectedLanguage") private var selectedLanguage = "en"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            // ✅ Image réelle ou fallback stylée
            ZStack {
                if let firstURL = plant.imageURLs.first, let url = URL(string: firstURL), !firstURL.isEmpty {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 130, height: 130)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } placeholder: {
                        ZStack {
                            Color(colorScheme == .dark ? "#2A2A2A" : "#F1F5ED")
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .black))
                        }
                        .frame(width: 130, height: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: colorScheme == .dark ? "#2A2A2A" : "#EAF1E7"))
                            .frame(width: 130, height: 130)

                        Image(systemName: "leaf")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .foregroundColor(Color(hex: "#263826"))
                    }
                }
            }

            // ✅ Texte
            VStack(spacing: 4) {
                Text(plant.localized["nom"] ?? plant.name)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "#263826"))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)

                Text((plant.localized["type"] ?? plant.type).isEmpty ? "Type inconnu" : (plant.localized["type"] ?? plant.type))
                    .font(.system(size: 13))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 5, x: 0, y: 2)
    }
}
