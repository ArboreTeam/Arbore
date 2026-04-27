import SwiftUI

/// UI shown while the user is tapping the floor to trace a new garden boundary
/// after choosing to replace manually.
struct BoundaryTracingOverlay: View {
    let pointCount: Int
    let area: Float                  // in m²
    let onCancel: () -> Void
    let onUndoLast: () -> Void
    let onValidate: () -> Void

    private var canValidate: Bool { pointCount >= 3 }

    var body: some View {
        VStack {
            // Top instruction banner
            VStack(spacing: 4) {
                Text("Tracez votre jardin")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Tapez le sol aux coins de votre jardin")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))

                HStack(spacing: 18) {
                    Label("\(pointCount) point\(pointCount > 1 ? "s" : "")", systemImage: "circle.dotted")
                        .font(.system(size: 12, weight: .medium))
                    if pointCount >= 3 {
                        Text(String(format: "%.1f m²", area))
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .foregroundStyle(.white)
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .padding(.top, 12)
            .padding(.horizontal, 16)

            Spacer()

            // Bottom action buttons
            HStack(spacing: 10) {
                actionButton(
                    title: "Annuler",
                    icon: "xmark",
                    tint: .red.opacity(0.85),
                    enabled: true,
                    action: onCancel
                )

                actionButton(
                    title: "Effacer",
                    icon: "arrow.uturn.backward",
                    tint: .gray.opacity(0.85),
                    enabled: pointCount > 0,
                    action: onUndoLast
                )

                actionButton(
                    title: "Valider la zone",
                    icon: "checkmark.circle.fill",
                    tint: Color(hex: "#2BEE79"),
                    enabled: canValidate,
                    action: onValidate
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
    }

    @ViewBuilder
    private func actionButton(title: String, icon: String, tint: Color, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(enabled ? tint : Color.gray.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .opacity(enabled ? 1.0 : 0.5)
        }
        .disabled(!enabled)
    }
}
