import SwiftUI

struct WaterReminderRow: View {
    let plantName: String
    let daysLeft: Int
    
    var body: some View {
        HStack {
            Image(systemName: "drop.fill")
                .foregroundColor(.blue)
            
            Text("\(plantName) - Arroser dans \(daysLeft) jour(s)")
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding()
        .background(Color.blue.opacity(0.2))
        .cornerRadius(10)
    }
}
