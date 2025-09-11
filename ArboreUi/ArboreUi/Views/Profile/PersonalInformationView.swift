import SwiftUI

struct PersonalInformationView: View {
    @State private var fullName: String = ""
    @State private var phoneNumber: String = ""
    @State private var email: String = ""
    @State private var address: String = ""
    @State private var citizenship: String = ""
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Personal Information")
                .font(.largeTitle)
                .bold()
                .padding(.top, 20)
                .padding(.horizontal)
            
            List {
                Section(header: Text("Name")) {
                    TextField("Full Name", text: $fullName)
                }
                
                Section(header: Text("Phone Number")) {
                    TextField("Phone Number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                }
                
                Section(header: Text("Email")) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                }
                
                Section(header: Text("Address")) {
                    TextField("Address", text: $address)
                }
                
                Section(header: Text("Citizenship")) {
                    TextField("Citizenship", text: $citizenship)
                }
                
                Button(action: {
                    // Save personal information logic
                }) {
                    Text("Save Changes")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
            }
        }
    }
}
