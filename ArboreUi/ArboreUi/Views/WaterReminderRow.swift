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
        .background(Color(hex: "#2A2A2A"))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(10)
    }
}
