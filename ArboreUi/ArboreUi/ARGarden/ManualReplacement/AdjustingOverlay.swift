import SwiftUI

/// Hint banner shown during the .adjusting phase. Tells the user how the
/// selection / drag / teleport gestures work. Designed to sit directly
/// under the topBar inside the main HUD VStack — not as a full-screen
/// overlay — so it never overlaps the back / undo / redo / validate row.
struct AdjustingHintBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Ajustez les plantes si besoin")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }
            Text("Visez une plante avec le réticule et tapez pour la sélectionner. Glissez ou tapez la nouvelle position pour la déplacer.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
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
    }
}

/// Action row shown during the .adjusting phase: revert ajustments + save.
/// Stays inside the main HUD VStack below the editingHUD so the layout
/// reflows naturally.
struct AdjustingActionButtons: View {
    let onRevert: () -> Void
    let onValidate: () -> Void

    var body: some View {
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
        .padding(.bottom, 16)
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
