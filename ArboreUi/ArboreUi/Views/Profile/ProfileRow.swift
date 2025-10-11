import SwiftUI

struct ProfileRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let title: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(themeManager.secondaryTextColor)
            Text(title)
                .foregroundColor(themeManager.textColor)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
