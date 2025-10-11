import SwiftUI

struct InfoCardView: View {
    let emoji: String
    let title: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji)
                .font(.system(size: 30))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
                Text(value)
                    .font(.body)
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
            }

            Spacer()
        }
        .padding()
        .background(colorScheme == .dark ? Color(hex: "#2A2A2A") : Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
        )
    }
}
