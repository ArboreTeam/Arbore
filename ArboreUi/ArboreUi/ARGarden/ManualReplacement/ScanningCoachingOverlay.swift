import SwiftUI

/// Bottom-anchored, non-blocking coaching UI shown while ARKit attempts to
/// relocalize a saved garden. Surface a "Replacer manuellement" button right
/// from the start so the user is never stuck if relocalization fails.
struct ScanningCoachingOverlay: View {
    let onReplaceManually: () -> Void

    @State private var pulse = false

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(ArboreDesign.Colors.softSurface.opacity(0.92))
                            .frame(width: 42, height: 42)

                        Image(systemName: "viewfinder")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(ArboreDesign.Colors.primaryGreen)
                            .scaleEffect(pulse ? 1.08 : 0.96)
                            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.t("AR_MANUAL_SCAN_TITLE"))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(ArboreDesign.Colors.textPrimary)
                        Text(L10n.t("AR_MANUAL_SCAN_SUBTITLE"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(ArboreDesign.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    ProgressView()
                        .tint(ArboreDesign.Colors.primaryGreen)
                }

                VStack(alignment: .leading, spacing: 8) {
                    scanStep(
                        icon: "iphone.gen3.radiowaves.left.and.right",
                        text: L10n.t("AR_REOPEN_SCAN_STEP_MOVE")
                    )
                    scanStep(
                        icon: "leaf",
                        text: L10n.t("AR_REOPEN_SCAN_STEP_RESTORE")
                    )
                }

                // Manual replacement entry-point — visible immediately.
                Button(action: onReplaceManually) {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.dashed.and.paperclip")
                            .font(.system(size: 15, weight: .semibold))
                        Text(L10n.t("AR_MANUAL_REPLACE"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(ArboreDesign.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                            .fill(ArboreDesign.Colors.softSurface.opacity(0.88))
                            .overlay(
                                RoundedRectangle(cornerRadius: ArboreDesign.Radius.button, style: .continuous)
                                    .strokeBorder(ArboreDesign.Colors.border.opacity(0.84), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(coachingCardBackground)
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .onAppear { pulse = true }
        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
    }

    private func scanStep(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ArboreDesign.Colors.primaryGreen)
                .frame(width: 22, height: 22)
                .background(ArboreDesign.Colors.primaryGreen.opacity(0.10), in: Circle())

            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(ArboreDesign.Colors.textSecondary)
                .lineLimit(2)
        }
    }

    private var coachingCardBackground: some View {
        RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                    .fill(ArboreDesign.Colors.card.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ArboreDesign.Radius.large, style: .continuous)
                    .stroke(ArboreDesign.Colors.border.opacity(0.86), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}
