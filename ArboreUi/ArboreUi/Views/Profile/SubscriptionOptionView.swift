import SwiftUI

struct SubscriptionOptionView: View {
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
                Spacer()
                Text(price)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            ForEach(features, id: \.self) { feature in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(feature)
                }
            }
        }
        .padding()
        .background(isHighlighted ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}
