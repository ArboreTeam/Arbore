import SwiftUI

struct MyGardenView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                
                Text("my_garden_title")
                    .font(.largeTitle)
                    .bold()
                    .padding(.horizontal)
                    .accessibilityLabel(Text("my_garden_title")) // VoiceOver lit la version localisée
                    .accessibilityAddTraits(.isHeader)

                Text("my_garden_description")
                    .font(.body)
                    .padding(.horizontal)
                    .accessibilityLabel(Text("my_garden_description")) // pour éviter les cas où le texte serait mal rendu

                Spacer()
            }
            .navigationTitle("") // supprime le titre dans la barre du haut
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
        }
    }
}
