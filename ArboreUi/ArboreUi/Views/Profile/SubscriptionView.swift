import SwiftUI

struct SubscriptionView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // Titre principal
                Text("Choisis ton abonnement")
                    .font(.largeTitle)
                    .bold()
                    .multilineTextAlignment(.center)
                    .padding(.top, 40)
                    .foregroundColor(themeManager.textColor)
                
                // Description
                Text("Accède à du contenu exclusif, débloque des fonctionnalités premium et améliore ton expérience.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(themeManager.secondaryTextColor)
                    .padding(.horizontal)
                
                // Carte d'abonnement mensuel
                SubscriptionOptionView(
                    title: "Mensuel",
                    price: "4,99€ / mois",
                    features: ["Accès illimité", "Mises à jour prioritaires", "Support premium"],
                    isHighlighted: false
                )
                .environmentObject(themeManager)
                
                // Carte d'abonnement annuel (mise en avant)
                SubscriptionOptionView(
                    title: "Annuel",
                    price: "49,99€ / an",
                    features: ["2 mois offerts", "Accès illimité", "Support premium"],
                    isHighlighted: true
                )
                .environmentObject(themeManager)
                
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
                    .foregroundColor(themeManager.secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 40)
            }
        }
        .background(themeManager.backgroundColor)
        .navigationTitle("Abonnement")
        .navigationBarTitleDisplayMode(.inline)
    }
}
