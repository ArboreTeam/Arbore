import SwiftUI

/// UI shown after the user confirmed the morphed placement. Plants are now
/// opaque and can be selected / dragged with the existing AR gestures.
/// Two actions are available:
///   - Annuler ajustements: reverts to the snapshot taken right after morphing
///   - Valider et sauvegarder: persists & dismisses
struct AdjustingOverlay: View {
    let onRevert: () -> Void
    let onValidate: () -> Void

    var body: some View {
        VStack {
            // Discreet hint banner at the top.
            HStack(spacing: 10) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Ajustez les plantes si besoin")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()

            HStack(spacing: 10) {
                actionButton(
                    title: "Annuler ajustements",
                    icon: "arrow.uturn.backward",
                    tint: .gray.opacity(0.85),
                    action: onRevert
                )
                actionButton(
                    title: "Valider et sauvegarder",
                    icon: "checkmark.seal.fill",
                    tint: Color(hex: "#2BEE79"),
                    action: onValidate
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
    }

    @ViewBuilder
    private func actionButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(tint)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
}
