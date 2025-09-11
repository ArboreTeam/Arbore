import SwiftUI

struct ProfileRow: View {
    let icon: String
    let title: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.gray)
            Text(title)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
