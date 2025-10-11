import SwiftUI

struct ToolCardView: View {
    let icon: String
    let title: String
    let description: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Color(hex: "#263826"))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
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
