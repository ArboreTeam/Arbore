import SwiftUI

struct PersonalInformationView: View {
    @State private var fullName: String = ""
    @State private var phoneNumber: String = ""
    @State private var email: String = ""
    @State private var address: String = ""
    @State private var citizenship: String = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color(hex: "#1A1A1A") : Color(hex: "#F1F5ED"))
                    .ignoresSafeArea()
                
                VStack(alignment: .leading) {
                    List {
                        Section(header: Text("Name").foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)) {
                            TextField("Full Name", text: $fullName)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .listRowBackground(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
                        
                        Section(header: Text("Phone Number").foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)) {
                            TextField("Phone Number", text: $phoneNumber)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .keyboardType(.phonePad)
                        }
                        .listRowBackground(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
                        
                        Section(header: Text("Email").foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)) {
                            TextField("Email", text: $email)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .keyboardType(.emailAddress)
                        }
                        .listRowBackground(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
                        
                        Section(header: Text("Address").foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)) {
                            TextField("Address", text: $address)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .listRowBackground(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
                        
                        Section(header: Text("Citizenship").foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)) {
                            TextField("Citizenship", text: $citizenship)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .listRowBackground(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
                        
                        Section {
                            Button(action: {
                                // Save personal information logic
                                dismiss()
                            }) {
                                Text("Save Changes")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(hex: "#2E7D32"))
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                            .padding()
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(colorScheme == .dark ? Color(hex: "#1A1A1A") : Color(hex: "#F1F5ED"))
                }
            }
            .navigationTitle("Personal Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "#2E7D32"))
                }
            }
        }
    }
}
