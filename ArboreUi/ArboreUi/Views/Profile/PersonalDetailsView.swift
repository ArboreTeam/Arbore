import SwiftUI

struct PersonalDetailsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var fullName: String = "Hugo Michel"
    @State private var phoneNumber: String = ""
    @State private var email: String = ""
    @State private var address: String = ""
    
    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            VStack {
                List {
                    Section(header: Text("Full Name")) {
                        TextField("Full Name", text: $fullName)
                    }
                    .listRowBackground(themeManager.cardBackgroundColor)
                    
                    Section(header: Text("Phone Number")) {
                        TextField("Phone Number", text: $phoneNumber)
                            .keyboardType(.phonePad)
                    }
                    .listRowBackground(themeManager.cardBackgroundColor)
                    
                    Section(header: Text("Email")) {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                    }
                    .listRowBackground(themeManager.cardBackgroundColor)
                    
                    Section(header: Text("Address")) {
                        TextField("Address", text: $address)
                    }
                    .listRowBackground(themeManager.cardBackgroundColor)
                    
                    Section {
                        Button(action: { dismiss() }) {
                            Text("Save Changes")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Personal Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}