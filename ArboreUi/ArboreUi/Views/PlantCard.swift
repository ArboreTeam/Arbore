import SwiftUI

struct PlantCard: View {
    let plant: Plant
    @AppStorage("selectedLanguage") private var selectedLanguage = "en"

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
                            Color(hex: "#F1F5ED")
                            ProgressView()
                        }
                        .frame(width: 130, height: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "#EAF1E7"))
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
                    .foregroundColor(Color(hex: "#263826"))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)

                Text((plant.localized["type"] ?? plant.type).isEmpty ? "Type inconnu" : (plant.localized["type"] ?? plant.type))
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}
