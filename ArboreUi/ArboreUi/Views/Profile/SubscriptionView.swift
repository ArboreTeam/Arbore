import SwiftUI

struct SubscriptionView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // Titre principal
                Text("Choisis ton abonnement")
                    .font(.largeTitle)
                    .bold()
                    .multilineTextAlignment(.center)
                    .padding(.top, 40)
                
                // Description
                Text("Accède à du contenu exclusif, débloque des fonctionnalités premium et améliore ton expérience.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                
                // Carte d'abonnement mensuel
                SubscriptionOptionView(
                    title: "Mensuel",
                    price: "4,99€ / mois",
                    features: ["Accès illimité", "Mises à jour prioritaires", "Support premium"],
                    isHighlighted: false
                )
                
                // Carte d'abonnement annuel (mise en avant)
                SubscriptionOptionView(
                    title: "Annuel",
                    price: "49,99€ / an",
                    features: ["2 mois offerts", "Accès illimité", "Support premium"],
                    isHighlighted: true
                )
                
                // Bouton continuer
                Button(action: {
                    // Logique future d'achat
                }) {
                    Text("Continuer")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                
                // Lien conditions
                Text("En continuant, tu acceptes les conditions d'utilisation.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 40)
            }
        }
        .navigationTitle("Abonnement")
        .navigationBarTitleDisplayMode(.inline)
    }
}
