import SwiftUI

/// Bottom-anchored, non-blocking coaching UI shown while ARKit attempts to
/// relocalize a saved garden. Surface a "Replacer manuellement" button right
/// from the start so the user is never stuck if relocalization fails.
struct ScanningCoachingOverlay: View {
    let onReplaceManually: () -> Void
    let onCancel: () -> Void

    @State private var pulse = false

    var body: some View {
        VStack {
            // Top-right cancel (X) — never the primary action, but always accessible.
            HStack {
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .padding(.trailing, 16)
                .padding(.top, 12)
            }

            Spacer()

            // Coaching card
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "viewfinder.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(Color(hex: "#2BEE79"))
                        .scaleEffect(pulse ? 1.08 : 0.95)
                        .opacity(pulse ? 1.0 : 0.75)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("AR_MANUAL_SCAN_TITLE"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(L10n.t("AR_MANUAL_SCAN_SUBTITLE"))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    ProgressView()
                        .tint(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        )
                )

                // Manual replacement entry-point — visible immediately.
                Button(action: onReplaceManually) {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.dashed.and.paperclip")
                            .font(.system(size: 15, weight: .semibold))
                        Text(L10n.t("AR_MANUAL_REPLACE"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(hex: "#2BEE79").opacity(0.85))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
        }
        .onAppear { pulse = true }
        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
    }
}
