import SwiftUI
import Firebase

struct ProfileView: View {
    @AppStorage("isLoggedIn") var isLoggedIn = false

    var body: some View {
        VStack(alignment: .leading) {
            Text("Hugo Michel")
                .font(.largeTitle)
                .bold()
                .padding(.top, 20)
                .padding(.horizontal)

            List {
                NavigationLink(destination: PersonalInformationView()) {
                    ProfileRow(icon: "person.fill", title: "Personal Information")
                }
                ProfileRow(icon: "creditcard.fill", title: "Payment Information")
                ProfileRow(icon: "house.fill", title: "Delivery Information")
                NavigationLink(destination: SettingsView()) {
                    ProfileRow(icon: "gearshape.fill", title: "Settings")
                }
                NavigationLink(destination: SubscriptionView()) {
                    ProfileRow(icon: "star.fill", title: "Abonnement")
                }
                ProfileRow(icon: "questionmark.circle.fill", title: "Help")

                Section {
                    Button(action: logout) {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.red)
                            Text("Log Out")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
    }

    func logout() {
        do {
            try Auth.auth().signOut()
            isLoggedIn = false
        } catch {
            print("Erreur de déconnexion Firebase :", error.localizedDescription)
        }
    }
}
