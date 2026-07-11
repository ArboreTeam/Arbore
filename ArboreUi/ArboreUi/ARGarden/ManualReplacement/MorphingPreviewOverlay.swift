import SwiftUI

/// Top status banner shown after the user validated their new boundary,
/// while plants are previewed at their morphed positions in golden ghost
/// form. Lives inside the main HUD VStack under the topBar so it never
/// collides with back/undo/redo buttons.
struct MorphingPreviewHintBanner: View {
    let warnings: [DistortionWarning]

    private var severeCount: Int { warnings.filter { $0.severity == .severe }.count }
    private var moderateCount: Int { warnings.filter { $0.severity == .moderate }.count }

    var body: some View {
        VStack(spacing: 8) {
            statusBanner
            if !warnings.isEmpty {
                warningsList
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        let (icon, title, subtitle, color): (String, String, String, Color) = {
            if warnings.isEmpty {
                return ("checkmark.seal.fill",
                        "Placement fiable",
                        "Toutes les plantes ont été placées avec succès",
                        Color(hex: "#2BEE79"))
            } else if severeCount > 0 {
                return ("exclamationmark.triangle.fill",
                        "\(severeCount + moderateCount) plante\(severeCount + moderateCount > 1 ? "s" : "") à vérifier",
                        "Certaines zones ont beaucoup changé",
                        .orange)
            } else {
                return ("info.circle.fill",
                        "\(moderateCount) plante\(moderateCount > 1 ? "s" : "") à surveiller",
                        "Légères différences de forme détectées",
                        .yellow)
            }
        }()

        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(color.opacity(0.45), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var warningsList: some View {
        let displayed = Array(warnings.prefix(5))
        let extra = warnings.count - displayed.count

        VStack(alignment: .leading, spacing: 6) {
            ForEach(displayed) { w in
                HStack(spacing: 8) {
                    Circle()
                        .fill(w.severity == .severe ? Color.orange : Color.yellow)
                        .frame(width: 8, height: 8)
                    Text(w.plantName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                    Text(w.zone)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
            }
            if extra > 0 {
                Text(L10n.f("AR_MORPHING_EXTRA_COUNT_FORMAT", extra))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.45))
        )
    }
}

/// Bottom action row for the morphing-preview phase. Lives inside the
/// main HUD VStack just above the safe-area bottom.
struct MorphingPreviewActionButtons: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            actionButton(
                title: "Annuler",
                icon: "xmark",
                tint: .red.opacity(0.85),
                action: onCancel
            )
            actionButton(
                title: "Confirmer le placement",
                icon: "checkmark.circle.fill",
                tint: Color(hex: "#2BEE79"),
                action: onConfirm
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
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
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
