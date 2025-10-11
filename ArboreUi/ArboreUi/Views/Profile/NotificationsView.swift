import SwiftUI

struct NotificationsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("reminderFrequency") private var reminderFrequency: Double = 1.0 // En jours
    
    var body: some View {
        ZStack {
            Color(hex: "#1A1A1A")
                .ignoresSafeArea()
            
            VStack(alignment: .leading) {
                Text("Notifications")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .padding(.horizontal)
                
                List {
                    Section(header: Text("Notification Settings").foregroundColor(.white.opacity(0.7))) {
                        Toggle(isOn: $notificationsEnabled) {
                            Text("Enable Notifications")
                                .foregroundColor(.white)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#263826")))
                    }
                    .listRowBackground(Color(hex: "#2A2A2A"))
                    
                    if notificationsEnabled {
                        Section(header: Text("Reminder Frequency").foregroundColor(.white.opacity(0.7))) {
                            VStack(alignment: .leading) {
                                Slider(value: $reminderFrequency, in: 1...7, step: 1) {
                                    Text("Frequency")
                                        .foregroundColor(.white)
                                }
                                .accentColor(Color(hex: "#263826"))
                                
                                Text("Remind me every \(Int(reminderFrequency)) day(s)")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .listRowBackground(Color(hex: "#2A2A2A"))
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color(hex: "#1A1A1A"))
            }
        }
    }
}
