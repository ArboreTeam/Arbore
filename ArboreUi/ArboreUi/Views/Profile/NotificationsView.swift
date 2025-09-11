import SwiftUI

struct NotificationsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("reminderFrequency") private var reminderFrequency: Double = 1.0 // En jours
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Notifications")
                .font(.largeTitle)
                .bold()
                .padding(.top, 20)
                .padding(.horizontal)
            
            List {
                Section(header: Text("Notification Settings")) {
                    Toggle(isOn: $notificationsEnabled) {
                        Text("Enable Notifications")
                    }
                }
                
                if notificationsEnabled {
                    Section(header: Text("Reminder Frequency")) {
                        Slider(value: $reminderFrequency, in: 1...7, step: 1) {
                            Text("Frequency")
                        }
                        Text("Remind me every \(Int(reminderFrequency)) day(s)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }
}
