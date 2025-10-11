import SwiftUI

struct SubscriptionOptionView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String
    let price: String
    let features: [String]
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .bold()
                    .foregroundColor(themeManager.textColor)
                Spacer()
                Text(price)
                    .font(.subheadline)
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            
            ForEach(features, id: \.self) { feature in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(feature)
                        .foregroundColor(themeManager.textColor)
                }
            }
        }
        .padding()
        .background(isHighlighted ? Color.green.opacity(0.1) : themeManager.cardBackgroundColor)
        .cornerRadius(16)
        .padding(.horizontal)
    }
}
